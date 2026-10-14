"""`kit.py init`: scaffolds the project files the kit expects.

Creates, from templates/, every file that does not exist yet and never
overwrites one that does: AGENTS.md (with CLAUDE.md and GEMINI.md pointing at
it), the agent skills, godot_kit.toml, the test folder (.gdignore, the
project's suite base, a suite template, a smoke suite) and .scratch/. Lines
the kit needs in .gitignore are appended when missing. Run it again after a
kit update to pick up new templates; existing files are listed as kept, so
diff them against templates/ by hand.
"""

from __future__ import annotations

import argparse
import re

from .project import CONFIG_NAME, KIT_DIR, KIT_PREFIX, Project, unquote

TEMPLATES = KIT_DIR / "templates"
# Template folder -> project folder ({{TEST_DIR}} is filled in).
_DESTINATIONS = {"claude": ".claude", "test": "{{TEST_DIR}}", "scratch": ".scratch"}
_RENDERERS = {"gl_compatibility": "GL Compatibility", "mobile": "Mobile", "forward_plus": "Forward+"}


def add_parser(subparsers: argparse._SubParsersAction, parents: list[argparse.ArgumentParser]) -> None:
    parser = subparsers.add_parser("init", parents=parents, help="Scaffold AGENTS.md, skills, test folder and config from the kit templates",
                                   description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="List what would be created without writing")


def placeholders(project: Project) -> dict[str, str]:
    settings = project.settings()
    application = settings.get("application", {})
    features = re.findall(r'"([^"]*)"', application.get("config/features", ""))
    feature_version = next((f for f in features if re.fullmatch(r"\d+(\.\d+)*", f)), "")
    method = unquote(settings.get("rendering", {}).get("renderer/rendering_method", '"forward_plus"'))
    return {
        "{{PROJECT_NAME}}": unquote(application.get("config/name", '"Godot project"')),
        "{{ENGINE_VERSION}}": project.config["engine"]["version"] or feature_version or "4",
        "{{RENDERER}}": _RENDERERS.get(method, method),
        "{{TEST_DIR}}": project.test_dir,
        "{{KIT}}": KIT_PREFIX,
        "{{PRODUCTION_DIRS}}": ", ".join(f'"{d}"' for d in _guess_production_dirs(project)),
        "{{OUTPUT_DIR}}": project.config["capture"]["output_dir"].rstrip("/"),
    }


def run(args: argparse.Namespace, project: Project) -> int:
    project.require_vendored("init")
    values = placeholders(project)
    created, kept = 0, 0
    for template in sorted(p for p in TEMPLATES.rglob("*") if p.is_file()):
        relative = template.relative_to(TEMPLATES).as_posix()
        if relative == ".gdignore":
            continue  # keeps Godot out of templates/ itself
        target = project.root / _fill(_destination(relative), values)
        if target.exists():
            kept += 1
            print(f"keep    {target.relative_to(project.root).as_posix()} (exists)")
            continue
        created += 1
        print(f"create  {target.relative_to(project.root).as_posix()}")
        if not args.dry_run:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(_fill(template.read_text(encoding="utf-8"), values), encoding="utf-8", newline="\n")
    appended = _update_gitignore(project, values, args.dry_run)
    print(f"\n[init] {created} created, {kept} kept, {len(appended)} .gitignore line(s) added{' (dry run)' if args.dry_run else ''}.")
    if (project.root / "AGENTS.md").exists() and kept:
        print(f"[init] Existing files were left alone. Compare them with {KIT_PREFIX}/templates/ (AGENTS.md §1-§4, the skills).")
    if not args.dry_run and not project.config["lint"]["production_dirs"] and (project.root / CONFIG_NAME).exists():
        print(f"[init] Check lint.production_dirs in {CONFIG_NAME}: production-code rules only look there.")
    return 0


def _destination(relative: str) -> str:
    first, _, rest = relative.partition("/")
    return f"{_DESTINATIONS[first]}/{rest}" if first in _DESTINATIONS and rest else relative


def _fill(text: str, values: dict[str, str]) -> str:
    for key, value in values.items():
        text = text.replace(key, value)
    return text


def _guess_production_dirs(project: Project) -> list[str]:
    """Top-level folders holding GDScript, except tooling, tests and add-ons."""
    skipped = {"addons", "tools", project.test_dir.split("/")[0], ".godot", ".scratch", ".git", ".claude"}
    found = []
    for folder in sorted(p for p in project.root.iterdir() if p.is_dir() and p.name not in skipped):
        if not (folder / ".gdignore").exists() and next(folder.rglob("*.gd"), None) is not None:
            found.append(folder.name + "/")
    return found


def _update_gitignore(project: Project, values: dict[str, str], dry_run: bool) -> list[str]:
    wanted = [".scratch/*", "!.scratch/.gdignore", f"{values['{{OUTPUT_DIR}}']}/", "__pycache__/"]
    path = project.root / ".gitignore"
    existing = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    missing = [line for line in wanted if line not in existing]
    for line in missing:
        print(f"append  .gitignore: {line}")
    if missing and not dry_run:
        prefix = "" if not existing or existing[-1] == "" else "\n"
        with path.open("a", encoding="utf-8", newline="\n") as handle:
            handle.write(prefix + "# godot-agent-kit\n" + "\n".join(missing) + "\n")
    return missing
