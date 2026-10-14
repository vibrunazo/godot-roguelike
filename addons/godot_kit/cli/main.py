"""Command line for godot-agent-kit. Run from the game's project root:

    python addons/godot_kit/kit.py <command> [options]

Commands:
    test           run test suites headlessly under a watchdog (lint first)
    scratch        run a throwaway -s script under a watchdog
    lint           run the project lint (no Godot needed)
    capture        screenshots, contact sheets and videos (needs a display)
    check-runners  prove the runners time out, clean up and catch script errors
    init           scaffold AGENTS.md, skills, test folder and config

Every command takes --project (default: the folder holding project.godot at or
above the working directory) and --config (default: <project>/godot_kit.toml).
Arguments after a bare -- are forwarded to `scratch` scripts and to the scene
`capture scene` captures.
"""

from __future__ import annotations

import argparse
import sys

from . import capture, check_runners, init, lint, scratch, tests
from .godot_env import resolve_godot
from .project import ConfigError, load_project

COMMANDS = {
    "test": tests,
    "scratch": scratch,
    "lint": lint,
    "capture": capture,
    "check-runners": check_runners,
    "init": init,
}
LAUNCHES_GODOT = {"test", "scratch", "capture", "check-runners"}


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--project", help="Godot project root (default: found from the working directory)")
    common.add_argument("--config", help="Config file (default: <project>/godot_kit.toml)")
    parser = argparse.ArgumentParser(prog="kit.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for module in COMMANDS.values():
        module.add_parser(subparsers, [common])
    return parser


def run(argv: list[str]) -> int:
    forwarded: list[str] = []
    if "--" in argv:
        split = argv.index("--")
        argv, forwarded = argv[:split], argv[split + 1:]
    args = build_parser().parse_args(argv)
    args.forwarded = forwarded
    takes_forwarded = args.command == "scratch" or (args.command == "capture" and args.mode == "scene")
    if forwarded and not takes_forwarded:
        command = f"{args.command} {args.mode}" if args.command == "capture" else args.command
        print(f"error: only `scratch` and `capture scene` take arguments after --, `{command}` got {' '.join(forwarded)}", file=sys.stderr)
        return 2
    try:
        project = load_project(args.project, args.config)
        if args.command in LAUNCHES_GODOT:
            # Fail once, up front, on a missing or wrong-version engine.
            resolve_godot(project)
        return COMMANDS[args.command].run(args, project)
    except ConfigError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
