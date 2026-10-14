"""Project discovery and the godot_kit.toml configuration.

Every command runs against one Godot project: --project when given, else the
nearest folder at or above the working directory that holds project.godot.
Its godot_kit.toml (or --config) overrides DEFAULTS below. Unknown keys and
wrongly typed values are errors, so a typo fails loudly instead of silently
doing nothing.
"""

from __future__ import annotations

import copy
import re
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

# The kit's own folder (the one holding kit.py).
KIT_DIR = Path(__file__).resolve().parent.parent
# Where a game vendors the kit. Suites extend the harness by this path, and the
# capture and runner-check scenes run from it.
KIT_PREFIX = "addons/godot_kit"
CONFIG_NAME = "godot_kit.toml"

DEFAULTS: dict[str, Any] = {
    "engine": {
        # Engine version the project is pinned to: "4.7.1", "4.7", or "" for any.
        "version": "",
    },
    "test": {
        "dir": "test",
        "timeout": 10,
        "fps": 60,
        # User arguments every suite run gets (OS.get_cmdline_user_args()),
        # e.g. ["--save-path=user://test_save.dat"] so tests never touch real saves.
        "user_args": [],
    },
    "scratch": {
        "timeout": 15,
        "fps": 60,
    },
    "lint": {
        # Folders holding game code (posix, trailing slash): "characters/".
        "production_dirs": [],
        "function_line_limit": 40,
        "test_function_line_limit": 60,
        # Extra per-prefix limits, e.g. {"tools/" = 80}.
        "function_line_limits": {"tools/": 80},
        # Docs that may name files that no longer exist (closed reviews).
        "historical_docs": ["docs/reviews/"],
        # Scripts a suite may extend; empty = the kit harness and <test>/lib/project_suite.gd.
        "harness_paths": [],
        # Assertion functions whose float-literal expectations look like tuning.
        "assert_functions": ["check_eq", "check_approx"],
        "allowed_load_suffixes": [".gdshader", ".gdshaderinc"],
        # Folders whose timers must run on the physics clock (gameplay code).
        "physics_clock_dirs": [],
        # [[lint.forbidden_references]] tables: dirs, names, optional reason.
        "forbidden_references": [],
        "disable": [],
        "enable": [],
    },
    "capture": {
        "output_dir": "movies",
        # Node paths hidden while capturing (HUDs, fades), e.g. "/root/UI".
        "hide_paths": [],
        # Class name `capture test` keeps in frame, e.g. "Character".
        "track_type": "",
        "screenshot_timeout": 25,
        "video_timeout": 90,
    },
}

# Tables whose keys are free-form (validated by value type only).
_FREE_FORM = {"lint.function_line_limits": int}


class ConfigError(Exception):
    """A missing project, a bad godot_kit.toml, or a command that cannot run here."""


@dataclass
class Project:
    """A Godot project and its merged kit configuration."""

    root: Path
    config: dict[str, Any]
    config_path: Optional[Path]

    @property
    def kit_vendored(self) -> bool:
        """True when the kit lives at KIT_PREFIX inside this project."""
        try:
            return KIT_DIR.resolve() == (self.root / KIT_PREFIX).resolve()
        except OSError:
            return False

    @property
    def kit_relative(self) -> Optional[str]:
        """The kit folder relative to the project root (posix), or None when outside."""
        try:
            return KIT_DIR.resolve().relative_to(self.root.resolve()).as_posix()
        except ValueError:
            return None

    @property
    def test_dir(self) -> str:
        return str(self.config["test"]["dir"]).replace("\\", "/").strip("/")

    def harness_paths(self) -> list[str]:
        configured: list[str] = self.config["lint"]["harness_paths"]
        if configured:
            return list(configured)
        return [f"res://{KIT_PREFIX}/harness/test_suite.gd", f"res://{self.test_dir}/lib/project_suite.gd"]

    def require_vendored(self, command: str) -> None:
        if not self.kit_vendored:
            raise ConfigError(
                f"'{command}' runs the kit's GDScript, so the kit must live at {KIT_PREFIX}/ inside the "
                f"project (it is at {KIT_DIR}). Vendor it there (see the kit README)."
            )

    def settings(self) -> dict[str, dict[str, str]]:
        """project.godot as {section: {key: raw value}} (single-line values only)."""
        return parse_project_godot(self.root / "project.godot")

    def autoload_names(self) -> list[str]:
        return sorted(self.settings().get("autoload", {}).keys())


def parse_project_godot(path: Path) -> dict[str, dict[str, str]]:
    sections: dict[str, dict[str, str]] = {"": {}}
    current = ""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return sections
    for line in text.splitlines():
        header = re.match(r"^\[([^\]]+)\]\s*$", line)
        if header:
            current = header.group(1)
            sections.setdefault(current, {})
            continue
        entry = re.match(r"^([A-Za-z0-9_/.\-]+)=(.*)$", line)
        if entry:
            sections[current][entry.group(1)] = entry.group(2).strip()
    return sections


def unquote(value: str) -> str:
    return value[1:-1] if len(value) >= 2 and value[0] == value[-1] == '"' else value


def find_root(start: Path) -> Optional[Path]:
    for folder in (start, *start.parents):
        if (folder / "project.godot").is_file():
            return folder
    return None


def load_project(project_arg: Optional[str], config_arg: Optional[str]) -> Project:
    """The project to work on, with its configuration merged over DEFAULTS."""
    if project_arg:
        root = Path(project_arg).resolve()
        if not (root / "project.godot").is_file():
            raise ConfigError(f"No project.godot in {root}.")
    else:
        found = find_root(Path.cwd().resolve())
        if found is None:
            raise ConfigError("No project.godot here or in any parent folder. Run from the game's project root or pass --project.")
        root = found
    config_path = Path(config_arg).resolve() if config_arg else root / CONFIG_NAME
    config = copy.deepcopy(DEFAULTS)
    if config_path.is_file():
        try:
            data = tomllib.loads(config_path.read_text(encoding="utf-8"))
        except tomllib.TOMLDecodeError as error:
            raise ConfigError(f"{config_path}: {error}") from error
        _merge(config, data, "")
    elif config_arg:
        raise ConfigError(f"Config file not found: {config_path}")
    else:
        config_path = None
    _validate(config)
    return Project(root, config, config_path)


def _merge(base: dict[str, Any], override: dict[str, Any], prefix: str) -> None:
    for key, value in override.items():
        dotted = f"{prefix}{key}"
        if key not in base:
            raise ConfigError(f"Unknown setting '{dotted}' in {CONFIG_NAME} (known: {', '.join(sorted(base))}).")
        if dotted in _FREE_FORM:
            if not isinstance(value, dict) or not all(isinstance(v, _FREE_FORM[dotted]) for v in value.values()):
                raise ConfigError(f"'{dotted}' must be a table of {_FREE_FORM[dotted].__name__} values.")
            base[key] = dict(value)
        elif isinstance(base[key], dict):
            if not isinstance(value, dict):
                raise ConfigError(f"'{dotted}' must be a table.")
            _merge(base[key], value, dotted + ".")
        else:
            if not _same_type(base[key], value):
                raise ConfigError(f"'{dotted}' must be {type(base[key]).__name__}, got {type(value).__name__}.")
            if isinstance(value, list) and dotted not in _TABLE_LISTS and not all(isinstance(v, str) for v in value):
                raise ConfigError(f"'{dotted}' must be a list of strings.")
            base[key] = value


# Lists of tables rather than lists of strings.
_TABLE_LISTS = {"lint.forbidden_references"}


def _same_type(default: Any, value: Any) -> bool:
    if isinstance(value, bool) or isinstance(default, bool):
        return isinstance(value, bool) and isinstance(default, bool)
    if isinstance(default, float):
        return isinstance(value, (int, float))
    return isinstance(value, type(default))


def _validate(config: dict[str, Any]) -> None:
    for entry in config["lint"]["forbidden_references"]:
        if not isinstance(entry, dict) or set(entry) - {"dirs", "names", "reason"}:
            raise ConfigError("Each [[lint.forbidden_references]] needs dirs and names (and an optional reason), nothing else.")
        for key in ("dirs", "names"):
            if not isinstance(entry.get(key), list) or not entry[key] or not all(isinstance(v, str) for v in entry[key]):
                raise ConfigError(f"[[lint.forbidden_references]] '{key}' must be a non-empty list of strings.")
    for key in ("production_dirs", "physics_clock_dirs", "historical_docs"):
        for folder in config["lint"][key]:
            if not str(folder).endswith("/"):
                raise ConfigError(f"lint.{key} entries are folders ending in '/': '{folder}'.")
