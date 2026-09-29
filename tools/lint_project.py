"""Project lint: mechanical checks for the rules in AGENTS.md.

Runs without Godot, in about two seconds, on every tracked (or new, not
ignored) file. Every violation fails the run: there is no baseline and no
suppression list. Fix the code, or fix the rule if it is wrong.

Usage:
    python tools/lint_project.py        # exit 1 if anything is reported

Rules (see the RULES table for the one-line reasons):
    uid-duplicate      two files own the same UID
    uid-noncanonical   a UID spelled in a way Godot would never generate
    uid-mismatch       an ext_resource UID owned by a different file than its path
    hardcoded-load     a res:// asset path in production code (loaded or kept for later)
    absolute-path      a machine-specific absolute path in code, scenes or docs
    test-key-constant  a physical key constant (KEY_*) in a test
    test-float-literal a check_eq/check_approx against a tuned-looking float literal
    test-stray-file    a file in test/ that is not a suite, test/lib or test/fixtures
    test-not-harness   a suite that does not extend the test harness
    compat-wording     "alias", "legacy" or "backward" in a production docstring
    missing-reference  a Markdown doc naming a project file that does not exist
    long-function      a GDScript function longer than its area's limit (FUNCTION_LINE_LIMITS)
    late-declaration   a top-level const or @export declared after the first func
    export-undocumented an @export without a ## docstring
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

PRODUCTION_DIRS = (
    "Character/", "Components/", "Enemy/", "Hazards/", "Items/", "Levels/",
    "Passives/", "Player/", "Singletons/", "StateMachine/", "UserInterface/",
)
# Longest allowed GDScript function, from the func line to its last body
# line. Production code: about twice the project's 90th percentile (21 lines),
# so it flags functions doing too many things, not normal code. Scenario tests
# (setup, act, check) and sequential dev tools get more room.
FUNCTION_LINE_LIMITS: tuple[tuple[str, int], ...] = (("test/", 60), ("tools/", 80))
PRODUCTION_FUNCTION_LINES = 40


def function_line_limit(path: str) -> int:
    for prefix, limit in FUNCTION_LINE_LIMITS:
        if path.startswith(prefix):
            return limit
    return PRODUCTION_FUNCTION_LINES
# Historical documents (closed reviews) may name files that no longer exist,
# and quote paths.
HISTORICAL_DOCS = ("docs/reviews/",)

RULES: dict[str, str] = {
    "uid-duplicate": "two files own the same UID; one of them was copied or hand-written",
    "uid-noncanonical": "hand-written UID; let Godot generate it or omit uid=",
    "uid-mismatch": "the UID belongs to a different file than the ext_resource path",
    "hardcoded-load": "wire assets and scenes through @export or GlobalVars, not res:// paths in code",
    "absolute-path": "machine-specific path; use res:// or a repo-relative path",
    "test-key-constant": "drive input by InputMap action name, never physical keys",
    "test-float-literal": "compare against values the test sets or reads from nodes",
    "test-stray-file": "test/ holds only suites, test/lib and test/fixtures",
    "test-not-harness": 'suites extend "res://test/lib/test_suite.gd"',
    "compat-wording": "no aliases or legacy paths: update the callers instead",
    "missing-reference": "the doc names a file that does not exist",
    "long-function": "split it: a function this long is doing several jobs",
    "late-declaration": "declare consts and exports before the first func",
    "export-undocumented": "document every @export with a ## docstring",
}

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

def project_files() -> list[str]:
    """Tracked files plus new ones that are not git-ignored, as posix paths."""
    try:
        out = subprocess.run(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
            cwd=ROOT, capture_output=True, text=True, check=True, timeout=30,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        out = "\n".join(
            str(p.relative_to(ROOT)).replace(os.sep, "/")
            for p in ROOT.rglob("*") if p.is_file() and ".git" not in p.parts
        )
    files = []
    for line in out.splitlines():
        line = line.strip()
        if line and (ROOT / line).is_file():
            files.append(line)
    return sorted(set(files))


def read(path: str) -> str:
    try:
        return (ROOT / path).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


class Report:
    def __init__(self) -> None:
        self.violations: list[dict[str, str]] = []

    def add(self, rule: str, path: str, line: int, detail: str, note: str = "") -> None:
        self.violations.append({"rule": rule, "file": path, "line": str(line), "detail": detail.strip()[:200], "note": note})


# --- Checks ----------------------------------------------------------------------

_HEADER_UID = re.compile(r'^\[gd_(?:scene|resource)\b[^\]]*\buid="(uid://[^"]+)"', re.M)
_EXT_RESOURCE = re.compile(r'^\[ext_resource\b[^\]]*\]', re.M)
_ATTR = re.compile(r'(\w+)="([^"]*)"')
_IMPORT_UID = re.compile(r'^uid="(uid://[^"]+)"', re.M)


def check_uids(files: list[str], report: Report) -> None:
    owners: dict[int, list[str]] = {}
    spellings: list[tuple[str, str, int]] = []  # (text, file, line)

    def own(text: str, owner_path: str, source: str, line: int) -> None:
        value = uid_text_to_id(text)
        if value is None:
            report.add("uid-noncanonical", source, line, text)
            return
        owners.setdefault(value, []).append(owner_path)
        spellings.append((text, source, line))

    for path in files:
        if path.endswith(".uid"):
            text = read(path).strip()
            if text.startswith("uid://"):
                own(text, path[: -len(".uid")], path, 1)
        elif path.endswith((".tscn", ".tres")):
            content = read(path)
            match = _HEADER_UID.search(content)
            if match:
                own(match.group(1), path, path, content[: match.start()].count("\n") + 1)
        elif path.endswith(".import"):
            content = read(path)
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

    for path in files:
        if not path.endswith((".tscn", ".tres")):
            continue
        content = read(path)
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
_ALLOWED_LOAD_SUFFIXES = (".gdshader", ".gdshaderinc")


def check_hardcoded_loads(files: list[str], report: Report) -> None:
    for path in files:
        if not (path.endswith(".gd") and path.startswith(PRODUCTION_DIRS)):
            continue
        for number, line in enumerate(read(path).splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            for match in _RES_PATH.finditer(line):
                if not match.group(1).endswith(_ALLOWED_LOAD_SUFFIXES):
                    report.add("hardcoded-load", path, number, line)


_ABSOLUTE = re.compile(r'(?<![\w/])(?:[A-Za-z]:[\\/](?:Users|Program|home|mnt|docs|dev|src)|/mnt/[a-z]/|/home/\w|/Users/\w|\.gemini[\\/])')


def check_absolute_paths(files: list[str], report: Report) -> None:
    for path in files:
        if not path.endswith((".gd", ".tscn", ".tres", ".godot", ".py", ".md", ".cfg", ".json")):
            continue
        if path.startswith(HISTORICAL_DOCS):
            continue
        for number, line in enumerate(read(path).splitlines(), 1):
            if _ABSOLUTE.search(line):
                report.add("absolute-path", path, number, line)


_KEY_CONSTANT = re.compile(r'\bKEY_[A-Z0-9_]+\b')
_FLOAT_CHECK = re.compile(r'\bcheck_(?:eq|approx)\(([^,]+),\s*(-?\d+\.\d+)\b')
_HARNESS = 'extends "res://test/lib/test_suite.gd"'


def check_tests(files: list[str], report: Report) -> None:
    for path in files:
        if not path.startswith("test/"):
            continue
        name = path[len("test/"):]
        in_support = name.startswith(("lib/", "fixtures/"))
        is_suite = re.fullmatch(r"test_\w+\.(gd|tscn)", name) is not None or re.fullmatch(r"test_\w+\.gd\.uid", name) is not None
        if not in_support and not is_suite and name != ".gdignore":
            report.add("test-stray-file", path, 1, name)
        if not path.endswith(".gd"):
            continue
        content = read(path)
        if is_suite and _HARNESS not in content:
            report.add("test-not-harness", path, 1, "suite does not extend the harness")
        for number, line in enumerate(content.splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            for match in _KEY_CONSTANT.finditer(line):
                report.add("test-key-constant", path, number, match.group(0))
            for match in _FLOAT_CHECK.finditer(line):
                if float(match.group(2)) not in (0.0, 1.0):
                    report.add("test-float-literal", path, number, line)


_COMPAT = re.compile(r'\b(alias(?:es|ed)?|legacy|backwards?[- ]compat\w*)\b', re.I)


def check_compat_wording(files: list[str], report: Report) -> None:
    for path in files:
        if not (path.endswith(".gd") and path.startswith(PRODUCTION_DIRS)):
            continue
        for number, line in enumerate(read(path).splitlines(), 1):
            if line.lstrip().startswith("##") and _COMPAT.search(line):
                report.add("compat-wording", path, number, line)


_DOC_REFERENCE = re.compile(r'`((?:res://)?[\w./-]+\.(?:gd|tscn|tres|res|py|md|gdshader|json|glb|uid))`')


def check_doc_references(files: list[str], report: Report) -> None:
    existing = set(files)
    for path in files:
        if not path.endswith(".md") or path.startswith(HISTORICAL_DOCS):
            continue
        base = Path(path).parent
        for number, line in enumerate(read(path).splitlines(), 1):
            for match in _DOC_REFERENCE.finditer(line):
                ref = match.group(1).replace("res://", "")
                if "/" not in ref or "..." in ref:
                    continue  # a bare file name, or an abbreviated path: skip
                if ref.startswith((".scratch/", "movies/")):
                    continue  # examples of throwaway or generated paths
                candidates = {ref, (base / ref).as_posix()}
                if not any(c in existing or (ROOT / c).exists() for c in candidates):
                    report.add("missing-reference", path, number, ref)


_FUNC = re.compile(r'^(?:static\s+)?func\s+(\w+)')


def check_gdscript_structure(files: list[str], report: Report) -> None:
    for path in files:
        if not (path.endswith(".gd") and (path.startswith(PRODUCTION_DIRS) or path.startswith(("test/", "tools/")))):
            continue
        lines = read(path).splitlines()
        seen_func = False
        current: tuple[str, int] | None = None
        last_body = 0

        limit = function_line_limit(path)

        def close(end: int) -> None:
            if current is not None:
                length = end - current[1] + 1
                if length > limit:
                    report.add("long-function", path, current[1], f"{current[0]}()", f"{length} lines, limit {limit}")

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
            if path.startswith(PRODUCTION_DIRS) and top_level and stripped.startswith("@export") and not stripped.startswith(("@export_group", "@export_category", "@export_subgroup")):
                previous = index - 2
                while previous >= 0 and lines[previous].strip().startswith("@"):
                    previous -= 1
                if previous < 0 or not lines[previous].strip().startswith("##"):
                    report.add("export-undocumented", path, index, stripped)
        close(last_body)


CHECKS = (
    check_uids,
    check_hardcoded_loads,
    check_absolute_paths,
    check_tests,
    check_compat_wording,
    check_doc_references,
    check_gdscript_structure,
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.parse_args()

    files = project_files()
    report = Report()
    for check in CHECKS:
        check(files, report)

    for violation in report.violations:
        location = f'{violation["file"]}:{violation["line"]}: [{violation["rule"]}] {violation["detail"]} {violation["note"]}'.rstrip()
        print(location, flush=True)
        print(f'    -> {RULES[violation["rule"]]}', flush=True)
    print(f"[lint] {len(files)} files, {len(report.violations)} violation(s)", flush=True)
    return 1 if report.violations else 0


if __name__ == "__main__":
    sys.exit(main())
