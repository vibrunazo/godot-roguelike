"""Project lint: mechanical checks for the rules in AGENTS.md.

Runs without Godot, in a couple of seconds, on every tracked (or new, not
ignored) file of the project except the vendored kit. Every violation fails
the run: there is no baseline and no suppression comment. Fix the code, or fix
the rule (godot_kit.toml, or the kit itself) if it is wrong.

Rules (RULES holds the one-line reason printed with each violation):
    uid-duplicate        two files own the same UID
    uid-noncanonical     a UID spelled in a way Godot would never generate
    uid-mismatch         an ext_resource UID owned by a different file than its path
    hardcoded-load       a res:// asset path in production code (loaded or kept for later)
    absolute-path        a machine-specific absolute path in code, scenes or docs
    test-key-constant    a physical key constant (KEY_*) in a test
    test-float-literal   an assertion against a tuned-looking float literal in a test
    test-stray-file      a file in the test folder that is not a suite, lib/ or fixtures/
    test-not-harness     a suite that does not extend the harness
    compat-wording       "alias", "legacy" or "backward" in a production docstring
    missing-reference    a Markdown doc naming a project file that does not exist
    long-function        a GDScript function longer than its folder's limit
    late-declaration     a top-level const or @export declared after the first func
    export-undocumented  an @export without a ## docstring
    autoload-null-check  a null check on an autoload (they always exist in game runs)
    forbidden-reference  a folder naming a class it must not depend on (configured)
    render-clock-timer   a gameplay timer on the render clock (configured folders)
    print-in-production  print() in production code (opt-in: lint.enable)
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from .project import ConfigError, Project

RULES: dict[str, tuple[str, bool]] = {
    "uid-duplicate": ("two files own the same UID; one of them was copied or hand-written", True),
    "uid-noncanonical": ("hand-written UID; let Godot generate it or omit uid=", True),
    "uid-mismatch": ("the UID belongs to a different file than the ext_resource path", True),
    "hardcoded-load": ("wire assets and scenes through @export or a registry autoload, not res:// paths in code", True),
    "absolute-path": ("machine-specific path; use res:// or a repo-relative path", True),
    "test-key-constant": ("drive input by InputMap action name, never physical keys", True),
    "test-float-literal": ("compare against values the test sets or reads from nodes, never tuned literals", True),
    "test-stray-file": ("the test folder holds only suites, lib/ and fixtures/", True),
    "test-not-harness": ("suites extend the harness (godot_kit.toml lint.harness_paths)", True),
    "compat-wording": ("no aliases or legacy paths: update the callers instead", True),
    "missing-reference": ("the doc names a file that does not exist", True),
    "long-function": ("split it: a function this long is doing several jobs", True),
    "late-declaration": ("declare consts and exports before the first func", True),
    "export-undocumented": ("document every @export with a ## docstring", True),
    "autoload-null-check": ("autoloads always exist in game runs; a null check only hides a broken autoload", True),
    "forbidden-reference": ("this folder must not depend on that class; talk through signals or the event bus", True),
    "render-clock-timer": ("gameplay timing runs on the physics clock: Timer.process_callback = TIMER_PROCESS_PHYSICS, create_timer(t, true, true)", True),
    "print-in-production": ("print() also runs in release builds; use print_verbose() for dev logs, push_warning()/push_error() for problems", False),
}


@dataclass
class Violation:
    rule: str
    file: str
    line: int
    detail: str
    note: str = ""
    reason: str = ""


@dataclass
class Report:
    enabled: set[str]
    violations: list[Violation] = field(default_factory=list)

    def add(self, rule: str, path: str, line: int, detail: str, note: str = "", reason: str = "") -> None:
        if rule in self.enabled:
            self.violations.append(Violation(rule, path, line, detail.strip()[:200], note, reason or RULES[rule][0]))


@dataclass
class Context:
    project: Project
    root: Path
    files: list[str]
    production: tuple[str, ...]
    test_prefix: str
    lint: dict

    def read(self, path: str) -> str:
        try:
            return (self.root / path).read_text(encoding="utf-8", errors="replace")
        except OSError:
            return ""

    def is_production_gd(self, path: str) -> bool:
        return path.endswith(".gd") and bool(self.production) and path.startswith(self.production)


# --- Godot UID text encoding (core/io/resource_uid.cpp) ----------------------
# Godot writes base 34 with digits a-y then 0-8; its decoder also accepts z
# and 9, so invented spellings still load. Canonical == Godot would write it.
_UID_CHARS = "abcdefghijklmnopqrstuvwxy012345678"
_UID_BASE = 34
_UID_CHAR_COUNT = ord("z") - ord("a")  # 25


def uid_text_to_id(text: str) -> int | None:
    body = text[len("uid://"):] if text.startswith("uid://") else text
    if not body:
        return None
    value = 0
    for ch in body:
        if "a" <= ch <= "z":
            digit = ord(ch) - ord("a")
        elif "0" <= ch <= "9":
            digit = ord(ch) - ord("0") + _UID_CHAR_COUNT
        else:
            return None
        value = value * _UID_BASE + digit
    return value & 0x7FFFFFFFFFFFFFFF


def uid_id_to_text(value: int) -> str:
    digits = []
    while True:
        digits.append(_UID_CHARS[value % _UID_BASE])
        value //= _UID_BASE
        if value == 0:
            break
    return "uid://" + "".join(reversed(digits))


# --- File discovery ------------------------------------------------------------

def project_files(project: Project) -> list[str]:
    """Tracked files plus new ones that are not git-ignored, as posix paths,
    without the vendored kit and the .godot cache."""
    root = project.root
    try:
        out = subprocess.run(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
            cwd=root, capture_output=True, text=True, check=True, timeout=30,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        out = "\n".join(
            str(p.relative_to(root)).replace(os.sep, "/")
            for p in root.rglob("*") if p.is_file() and ".git" not in p.parts
        )
    skipped = [".godot/"]
    if project.kit_relative:
        skipped.append(project.kit_relative.rstrip("/") + "/")
    files = []
    for line in out.splitlines():
        line = line.strip()
        if line and not line.startswith(tuple(skipped)) and (root / line).is_file():
            files.append(line)
    return sorted(set(files))


def code_part(line: str) -> str:
    """The line without its trailing comment (a # outside string literals)."""
    quote = ""
    for index, ch in enumerate(line):
        if quote:
            if ch == quote and line[index - 1] != "\\":
                quote = ""
        elif ch in ('"', "'"):
            quote = ch
        elif ch == "#":
            return line[:index]
    return line


def code_lines(text: str) -> list[tuple[int, str]]:
    """(line number, code without comments) for every line that has code."""
    found = []
    for number, line in enumerate(text.splitlines(), 1):
        code = code_part(line)
        if code.strip():
            found.append((number, code))
    return found


# --- Checks ----------------------------------------------------------------------

_HEADER_UID = re.compile(r'^\[gd_(?:scene|resource)\b[^\]]*\buid="(uid://[^"]+)"', re.M)
_EXT_RESOURCE = re.compile(r'^\[ext_resource\b[^\]]*\]', re.M)
_ATTR = re.compile(r'(\w+)="([^"]*)"')
_IMPORT_UID = re.compile(r'^uid="(uid://[^"]+)"', re.M)


def check_uids(ctx: Context, report: Report) -> None:
    owners: dict[int, list[str]] = {}
    spellings: list[tuple[str, str, int]] = []  # (text, file, line)

    def own(text: str, owner_path: str, source: str, line: int) -> None:
        value = uid_text_to_id(text)
        if value is None:
            report.add("uid-noncanonical", source, line, text)
            return
        owners.setdefault(value, []).append(owner_path)
        spellings.append((text, source, line))

    for path in ctx.files:
        if path.endswith(".uid"):
            text = ctx.read(path).strip()
            if text.startswith("uid://"):
                own(text, path[: -len(".uid")], path, 1)
        elif path.endswith((".tscn", ".tres")):
            content = ctx.read(path)
            match = _HEADER_UID.search(content)
            if match:
                own(match.group(1), path, path, content[: match.start()].count("\n") + 1)
        elif path.endswith(".import"):
            content = ctx.read(path)
            match = _IMPORT_UID.search(content)
            if match:
                own(match.group(1), path[: -len(".import")], path, content[: match.start()].count("\n") + 1)

    for value, paths in owners.items():
        distinct = sorted(set(paths))
        if len(distinct) > 1:
            report.add("uid-duplicate", distinct[0], 1, f"{uid_id_to_text(value)} also owned by {', '.join(distinct[1:])}")

    for text, source, line in spellings:
        value = uid_text_to_id(text)
        if value is not None and uid_id_to_text(value) != text:
            report.add("uid-noncanonical", source, line, f"{text} (canonical: {uid_id_to_text(value)})")

    for path in ctx.files:
        if not path.endswith((".tscn", ".tres")):
            continue
        content = ctx.read(path)
        for match in _EXT_RESOURCE.finditer(content):
            attrs = dict(_ATTR.findall(match.group(0)))
            uid, res_path = attrs.get("uid", ""), attrs.get("path", "")
            if not uid:
                continue
            line = content[: match.start()].count("\n") + 1
            value = uid_text_to_id(uid)
            if value is None:
                report.add("uid-noncanonical", path, line, uid)
                continue
            if uid_id_to_text(value) != uid:
                report.add("uid-noncanonical", path, line, f"{uid} (canonical: {uid_id_to_text(value)})")
            target = res_path.replace("res://", "")
            owned_by = owners.get(value)
            # Binary resources (.res, imported assets without sidecars) carry
            # their UID inside the file; only text-visible owners are checked.
            if owned_by and target and target not in owned_by:
                report.add("uid-mismatch", path, line, f"{uid} points at {res_path} but belongs to {', '.join(sorted(set(owned_by)))}")


_RES_PATH = re.compile(r'"res://([^"]+)"')


def check_hardcoded_loads(ctx: Context, report: Report) -> None:
    allowed = tuple(ctx.lint["allowed_load_suffixes"])
    for path in ctx.files:
        if not ctx.is_production_gd(path):
            continue
        for number, line in enumerate(ctx.read(path).splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            for match in _RES_PATH.finditer(line):
                if not match.group(1).endswith(allowed):
                    report.add("hardcoded-load", path, number, line)


_ABSOLUTE = re.compile(r'(?<![\w/])(?:[A-Za-z]:[\\/](?:Users|Program|home|mnt|docs|dev|src)|/mnt/[a-z]/|/home/\w|/Users/\w|\.gemini[\\/])')


def check_absolute_paths(ctx: Context, report: Report) -> None:
    historical = tuple(ctx.lint["historical_docs"])
    for path in ctx.files:
        if not path.endswith((".gd", ".tscn", ".tres", ".godot", ".py", ".md", ".cfg", ".json", ".toml")):
            continue
        if historical and path.startswith(historical):
            continue
        for number, line in enumerate(ctx.read(path).splitlines(), 1):
            if _ABSOLUTE.search(line):
                report.add("absolute-path", path, number, line)


_KEY_CONSTANT = re.compile(r'\bKEY_[A-Z0-9_]+\b')
_EXTENDS_PATH = re.compile(r'^extends\s+"([^"]+)"', re.M)


def check_tests(ctx: Context, report: Report) -> None:
    names = "|".join(re.escape(name) for name in ctx.lint["assert_functions"])
    float_check = re.compile(r'\b(?:' + names + r')\(([^,]+),\s*(-?\d+\.\d+)\b') if names else None
    harnesses = set(ctx.project.harness_paths())
    for path in ctx.files:
        if not path.startswith(ctx.test_prefix):
            continue
        name = path[len(ctx.test_prefix):]
        in_support = name.startswith(("lib/", "fixtures/"))
        is_suite = re.fullmatch(r"test_\w+\.(gd|tscn)", name) is not None or re.fullmatch(r"test_\w+\.gd\.uid", name) is not None
        if not in_support and not is_suite and name != ".gdignore":
            report.add("test-stray-file", path, 1, name)
        if not path.endswith(".gd"):
            continue
        content = ctx.read(path)
        if is_suite:
            extended = _EXTENDS_PATH.search(content)
            if extended is None or extended.group(1) not in harnesses:
                report.add("test-not-harness", path, 1, "suite does not extend the harness")
        for number, line in enumerate(content.splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            for match in _KEY_CONSTANT.finditer(line):
                report.add("test-key-constant", path, number, match.group(0))
            if float_check is None:
                continue
            for match in float_check.finditer(line):
                if float(match.group(2)) not in (0.0, 1.0):
                    report.add("test-float-literal", path, number, line)


_COMPAT = re.compile(r'\b(alias(?:es|ed)?|legacy|backwards?[- ]compat\w*)\b', re.I)


def check_compat_wording(ctx: Context, report: Report) -> None:
    for path in ctx.files:
        if not ctx.is_production_gd(path):
            continue
        for number, line in enumerate(ctx.read(path).splitlines(), 1):
            if line.lstrip().startswith("##") and _COMPAT.search(line):
                report.add("compat-wording", path, number, line)


_DOC_REFERENCE = re.compile(r'`((?:res://)?[\w./-]+\.(?:gd|tscn|tres|res|py|md|gdshader|json|glb|uid|toml))`')


def check_doc_references(ctx: Context, report: Report) -> None:
    existing = set(ctx.files)
    historical = tuple(ctx.lint["historical_docs"])
    throwaway = (".scratch/", ctx.project.config["capture"]["output_dir"].rstrip("/") + "/")
    for path in ctx.files:
        if not path.endswith(".md") or (historical and path.startswith(historical)):
            continue
        base = Path(path).parent
        for number, line in enumerate(ctx.read(path).splitlines(), 1):
            for match in _DOC_REFERENCE.finditer(line):
                ref = match.group(1).replace("res://", "")
                if "/" not in ref or "..." in ref:
                    continue  # a bare file name, or an abbreviated path: skip
                if ref.startswith(throwaway):
                    continue  # examples of throwaway or generated paths
                candidates = {ref, (base / ref).as_posix()}
                if not any(c in existing or (ctx.root / c).exists() for c in candidates):
                    report.add("missing-reference", path, number, ref)


_FUNC = re.compile(r'^(?:static\s+)?func\s+(\w+)')


def _function_limit(ctx: Context, path: str) -> int | None:
    """The longest function allowed in path, or None when its folder is not checked."""
    if path.startswith(ctx.test_prefix):
        return int(ctx.lint["test_function_line_limit"])
    for prefix, limit in ctx.lint["function_line_limits"].items():
        if path.startswith(prefix):
            return int(limit)
    if ctx.production and path.startswith(ctx.production):
        return int(ctx.lint["function_line_limit"])
    return None


def check_gdscript_structure(ctx: Context, report: Report) -> None:
    for path in ctx.files:
        limit = _function_limit(ctx, path) if path.endswith(".gd") else None
        if limit is None:
            continue
        _check_structure_of(ctx, path, limit, report)


def _check_structure_of(ctx: Context, path: str, limit: int, report: Report) -> None:
    lines = ctx.read(path).splitlines()
    production = ctx.is_production_gd(path)
    seen_func = False
    current: tuple[str, int] | None = None
    last_body = 0

    def close(end: int) -> None:
        if current is not None and end - current[1] + 1 > limit:
            report.add("long-function", path, current[1], f"{current[0]}()", f"{end - current[1] + 1} lines, limit {limit}")

    for index, line in enumerate(lines, 1):
        stripped = line.strip()
        top_level = line[:1] not in (" ", "\t") and stripped != ""
        if top_level and not stripped.startswith("#"):
            match = _FUNC.match(line)
            close(last_body)
            current = (match.group(1), index) if match else None
            last_body = index
            if match:
                seen_func = True
            elif seen_func and (stripped.startswith("const ") or stripped.startswith("@export")):
                report.add("late-declaration", path, index, stripped)
        elif stripped and not stripped.startswith("#"):
            last_body = index
        if production and top_level and stripped.startswith("@export") and not stripped.startswith(("@export_group", "@export_category", "@export_subgroup")):
            previous = index - 2
            while previous >= 0 and lines[previous].strip().startswith("@"):
                previous -= 1
            if previous < 0 or not lines[previous].strip().startswith("##"):
                report.add("export-undocumented", path, index, stripped)
    close(last_body)


def check_autoload_null_checks(ctx: Context, report: Report) -> None:
    names = ctx.project.autoload_names()
    if not names:
        return
    alternatives = "|".join(re.escape(name) for name in names)
    # "if Globals", "not Globals", "x if Globals else y", "Globals and ...":
    # the autoload used as a value, not followed by a member access or call.
    pattern = re.compile(
        r'(?:\b(?:if|elif|and|or|not|while)\s+(?:' + alternatives + r')\b(?!\s*[.(\[])'
        r'|\b(?:' + alternatives + r')\s+(?:and|or)\b)'
    )
    for path in ctx.files:
        if not ctx.is_production_gd(path):
            continue
        for number, code in code_lines(ctx.read(path)):
            if pattern.search(code):
                report.add("autoload-null-check", path, number, code)


def check_forbidden_references(ctx: Context, report: Report) -> None:
    for entry in ctx.lint["forbidden_references"]:
        dirs = tuple(entry["dirs"])
        word = re.compile(r'\b(' + "|".join(re.escape(n) for n in entry["names"]) + r')\b')
        reason = entry.get("reason", "")
        for path in ctx.files:
            if not (path.endswith(".gd") and path.startswith(dirs)):
                continue
            for number, code in code_lines(ctx.read(path)):
                for match in word.finditer(code):
                    report.add("forbidden-reference", path, number, code, f"names {match.group(1)}", reason)


_CREATE_TIMER = re.compile(r'\bcreate_timer\(')
_TIMER_NODE = re.compile(r'^\[node\b[^\]]*\btype="Timer"', re.M)


def check_render_clock_timers(ctx: Context, report: Report) -> None:
    dirs = tuple(ctx.lint["physics_clock_dirs"])
    if not dirs:
        return
    for path in ctx.files:
        if not path.startswith(dirs):
            continue
        if path.endswith(".gd"):
            _check_timers_in_script(ctx, path, report)
        elif path.endswith(".tscn"):
            _check_timers_in_scene(ctx, path, report)


def _check_timers_in_script(ctx: Context, path: str, report: Report) -> None:
    text = ctx.read(path)
    physics_timers = "TIMER_PROCESS_PHYSICS" in text
    for number, code in code_lines(text):
        if "Timer.new()" in code and not physics_timers:
            report.add("render-clock-timer", path, number, code, "Timer without process_callback = TIMER_PROCESS_PHYSICS")
        for match in _CREATE_TIMER.finditer(code):
            arguments = _call_arguments(code, match.end())
            if arguments is not None and (len(arguments) < 3 or arguments[2] != "true"):
                report.add("render-clock-timer", path, number, code, "create_timer without process_in_physics = true")


def _check_timers_in_scene(ctx: Context, path: str, report: Report) -> None:
    text = ctx.read(path)
    for match in _TIMER_NODE.finditer(text):
        end = text.find("\n[", match.end())
        block = text[match.start(): end if end >= 0 else len(text)]
        if not re.search(r'^process_callback = 0\s*$', block, re.M):
            report.add("render-clock-timer", path, text[: match.start()].count("\n") + 1, match.group(0), "Timer node without process_callback = Physics")


def _call_arguments(code: str, start: int) -> list[str] | None:
    """Top-level arguments of the call whose '(' ends at start, or None if it does not close on this line."""
    depth, current, arguments = 0, "", []
    for ch in code[start:]:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0:
                if current.strip():
                    arguments.append(current.strip())
                return arguments
            depth -= 1
        elif ch == "," and depth == 0:
            arguments.append(current.strip())
            current = ""
            continue
        current += ch
    return None


_PRINT = re.compile(r'\b(?:print|prints|printt|printraw|print_rich)\(')


def check_prints(ctx: Context, report: Report) -> None:
    for path in ctx.files:
        if not ctx.is_production_gd(path):
            continue
        for number, code in code_lines(ctx.read(path)):
            if _PRINT.search(code):
                report.add("print-in-production", path, number, code)


CHECKS: tuple[Callable[[Context, Report], None], ...] = (
    check_uids,
    check_hardcoded_loads,
    check_absolute_paths,
    check_tests,
    check_compat_wording,
    check_doc_references,
    check_gdscript_structure,
    check_autoload_null_checks,
    check_forbidden_references,
    check_render_clock_timers,
    check_prints,
)


def enabled_rules(lint_config: dict) -> set[str]:
    unknown = [r for r in [*lint_config["enable"], *lint_config["disable"]] if r not in RULES]
    if unknown:
        raise ConfigError(f"Unknown lint rule(s) in godot_kit.toml: {', '.join(unknown)} (known: {', '.join(RULES)}).")
    enabled = {rule for rule, (_, default) in RULES.items() if default}
    return (enabled | set(lint_config["enable"])) - set(lint_config["disable"])


def lint_project(project: Project) -> tuple[list[Violation], int]:
    """Every violation in the project, and how many files were checked."""
    lint_config = project.config["lint"]
    files = project_files(project)
    ctx = Context(project, project.root, files, tuple(lint_config["production_dirs"]), project.test_dir + "/", lint_config)
    report = Report(enabled_rules(lint_config))
    for check in CHECKS:
        check(ctx, report)
    return report.violations, len(files)


def run_lint(project: Project) -> bool:
    """Prints every violation and a summary; True when there are none."""
    violations, file_count = lint_project(project)
    for v in violations:
        print(f"{v.file}:{v.line}: [{v.rule}] {v.detail} {v.note}".rstrip(), flush=True)
        print(f"    -> {v.reason}", flush=True)
    if not project.config["lint"]["production_dirs"]:
        print("[lint] note: lint.production_dirs is empty in godot_kit.toml, so production-code rules check nothing.", flush=True)
    print(f"[lint] {file_count} files, {len(violations)} violation(s)", flush=True)
    return not violations


def add_parser(subparsers: argparse._SubParsersAction, parents: list[argparse.ArgumentParser]) -> None:
    subparsers.add_parser("lint", parents=parents, help="Run the project lint (no Godot needed)",
                          description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)


def run(args: argparse.Namespace, project: Project) -> int:
    return 0 if run_lint(project) else 1
