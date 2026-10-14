"""`kit.py capture`: screenshots, contact sheets and videos of scenes and suites.

    kit.py capture scene <scene.tscn>               one screenshot (isometric preset)
    kit.py capture scene <scene.tscn> --preset all  every preset angle
    kit.py capture scene <scene.tscn> --scene-camera --at 3
                                                    what the scene's own camera shows after 3 s
    kit.py capture scene <scene.tscn> --sheet 6 --duration 4
                                                    6 frames over 4 s tiled into one image
    kit.py capture scene <scene.tscn> --video --duration 4
    kit.py capture scene <stage.tscn> --scene-camera -- --enemy=brute
                                                    arguments after -- go to the captured scene
    kit.py capture test <test/test_x.tscn>          record a suite as it runs (MP4)

Output lands in capture.output_dir (movies/ by default, git-ignored).
Screenshots are saved 768 px wide by default to keep them cheap to look at
(the frame still renders at full resolution); --full-res keeps every pixel.
Captures need a display and a GPU renderer: they cannot run --headless.

Arguments after `--` are forwarded to the captured scene: it finds them in
OS.get_cmdline_user_args() after the `--scene-args` marker. A project stages its
own captures this way (a character playing one animation, a scripted fight)
as a scene that reads its arguments, sets up the actors and its camera, and
leaves screenshots, sheets, video and quitting to the capturer.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import time
from pathlib import Path
from typing import Callable, Optional

from .godot_env import ensure_class_cache, run_godot
from .project import KIT_PREFIX, Project

SCENE_CAPTURER = f"{KIT_PREFIX}/capture/scene_capturer.tscn"
TEST_CAPTURER = f"{KIT_PREFIX}/capture/test_capturer.tscn"
PRESETS = ["isometric", "top_down", "front", "side", "overview", "all"]
# Separates the capturer's own user arguments from those forwarded to the scene.
SCENE_ARGS = "--scene-args"
# Lines streamed live; everything else is shown only on failure or --verbose.
LIVE_TAGS = ("[SceneCapturer]", "[TestCapturer]", "Screenshot saved", "Done recording")


def add_parser(subparsers: argparse._SubParsersAction, parents: list[argparse.ArgumentParser]) -> None:
    # --project/--config live on the modes only: argparse would reset a value
    # given before the mode to the mode's default.
    parser = subparsers.add_parser("capture", help="Screenshots, contact sheets and videos of scenes and suites",
                                   description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    modes = parser.add_subparsers(dest="mode", required=True)
    scene = modes.add_parser("scene", parents=parents, help="Capture a scene from a preset angle, its own camera or a custom one")
    scene.add_argument("scene", help="Scene to capture (e.g. maps/arena/arena.tscn)")
    scene.add_argument("--preset", choices=PRESETS, default="isometric", help="Camera preset angle")
    scene.add_argument("--scene-camera", action="store_true", help="Keep the scene's own current camera instead of a preset")
    scene.add_argument("--at", type=float, default=0.25, help="Game seconds to run before the screenshot (default 0.25)")
    scene.add_argument("--sheet", type=int, help="Contact sheet of N frames spread over --duration instead of one screenshot")
    scene.add_argument("--cam-pos", help="Camera position X,Y,Z")
    scene.add_argument("--cam-target", help="Camera look-at target X,Y,Z")
    scene.add_argument("--target-node", help="Name of the node to frame")
    scene.add_argument("--cam-fov", type=float, help="Camera FOV in degrees")
    scene.add_argument("--cam-dist", type=float, help="Camera distance multiplier")
    scene.add_argument("--cam-height", type=float, help="Camera height offset")
    scene.add_argument("--cam-size", type=float, help="Orthographic camera size")
    scene.add_argument("--ortho", action="store_true", help="Orthographic projection")
    scene.add_argument("--freeze", action="store_true", help="Stop the scene's processing (a still life of its first frames)")
    _add_common(scene, video=True)
    test = modes.add_parser("test", parents=parents, help="Record a test suite as it runs")
    test.add_argument("test", help="Suite scene (e.g. test/test_x.tscn)")
    _add_common(test, video=False)


def _add_common(parser: argparse.ArgumentParser, video: bool) -> None:
    if video:
        parser.add_argument("--video", action="store_true", help="Record a video instead of a screenshot")
    parser.add_argument("--duration", type=float, help="Seconds to record (video, sheet, test)")
    parser.add_argument("--debug-collisions", action="store_true", help="Draw collision shapes")
    parser.add_argument("--show-ui", action="store_true", help="Keep capture.hide_paths and the capture_hidden group visible")
    parser.add_argument("--output", help="Output file (default: <output_dir>/<scene>_<mode>.png/.mp4)")
    parser.add_argument("--keep-avi", action="store_true", help="Keep the intermediate AVI")
    parser.add_argument("--gif", action="store_true", help="Also write an animated GIF")
    parser.add_argument("--full-res", action="store_true", help="Save screenshots at full resolution (default 768 px wide)")
    parser.add_argument("--verbose", action="store_true", help="Stream all engine output")


def run(args: argparse.Namespace, project: Project) -> int:
    project.require_vendored("capture")
    if not ensure_class_cache(project):
        return 1
    output_dir = project.root / project.config["capture"]["output_dir"]
    output_dir.mkdir(parents=True, exist_ok=True)
    return _capture_scene(args, project, output_dir) if args.mode == "scene" else _capture_test(args, project, output_dir)


def _common_user_args(args: argparse.Namespace, project: Project, output_dir: Path) -> list[str]:
    user_args = [f"--output-dir={output_dir.relative_to(project.root).as_posix()}"]
    if not args.show_ui:
        user_args += [f"--hide-path={p}" for p in project.config["capture"]["hide_paths"]] + ["--hide-ui"]
    if args.debug_collisions:
        user_args.append("--debug-collisions")
    if args.full_res:
        user_args.append("--shot-width=0")
    return user_args


def _capture_scene(args: argparse.Namespace, project: Project, output_dir: Path) -> int:
    user_args = [f"--scene={args.scene}", f"--preset={args.preset}", f"--at={args.at}"] + _common_user_args(args, project, output_dir)
    options = {"--cam-pos": args.cam_pos, "--cam-target": args.cam_target, "--target-node": args.target_node,
               "--cam-fov": args.cam_fov, "--cam-dist": args.cam_dist, "--cam-height": args.cam_height, "--cam-size": args.cam_size}
    user_args += [f"{key}={value}" for key, value in options.items() if value is not None]
    user_args += [flag for flag, on in (("--scene-camera", args.scene_camera), ("--cam-ortho", args.ortho), ("--freeze", args.freeze)) if on]
    name = Path(args.scene).stem
    if args.video:
        view = "scene" if args.scene_camera else args.preset
        return _record(args, project, SCENE_CAPTURER, user_args, output_dir / f"{name}_{view}.mp4", args.duration or 3.0)
    if args.sheet:
        user_args += [f"--sheet={args.sheet}", f"--duration={args.duration or 3.0}"]
        if args.output:
            user_args.append(f"--output={args.output}")
        # Frames advance a fixed 1/60 s of game time each, so --at and sheet times are exact.
        timeout = project.config["capture"]["screenshot_timeout"] + int(args.duration or 3.0)
        return _report(_launch(project, ["--fixed-fps", "60"], user_args, SCENE_CAPTURER, timeout, args), "Contact sheet")
    if args.output:
        user_args.append(f"--output={args.output}")
    timeout = project.config["capture"]["screenshot_timeout"] + int(args.at)
    return _report(_launch(project, ["--fixed-fps", "60"], user_args, SCENE_CAPTURER, timeout, args), "Screenshot")


def _capture_test(args: argparse.Namespace, project: Project, output_dir: Path) -> int:
    user_args = [f"--test={args.test}", *project.config["test"]["user_args"]] + _common_user_args(args, project, output_dir)
    track = project.config["capture"]["track_type"]
    if track:
        user_args.append(f"--track-type={track}")
    return _record(args, project, TEST_CAPTURER, user_args, output_dir / f"{Path(args.test).stem}.mp4", args.duration or 5.0)


def _record(args: argparse.Namespace, project: Project, capturer: str, user_args: list[str], default_mp4: Path, duration: float) -> int:
    # Absolute paths, so Godot's movie writer and ffmpeg agree on them.
    mp4 = (project.root / args.output) if args.output else default_mp4
    if mp4.suffix != ".mp4":
        mp4 = mp4.with_suffix(".mp4")
    mp4.parent.mkdir(parents=True, exist_ok=True)
    avi = mp4.with_name(f"temp_{mp4.stem}_{int(time.time())}.avi")
    user_args = [*user_args, "--video", f"--duration={duration}"]
    timeout = project.config["capture"]["video_timeout"] + int(duration * 4)
    code = _launch(project, ["--write-movie", avi.as_posix()], user_args, capturer, timeout, args)
    if code != 0:
        return code
    final = convert_avi_to_mp4(avi, mp4, args.keep_avi, args.gif)
    print(f"\n[SUCCESS] Video saved: {final}" if final else "\n[FAILED] No video was written.", flush=True)
    return 0 if final else 1


def _launch(project: Project, godot_flags: list[str], user_args: list[str], capturer: str, timeout: int, args: argparse.Namespace) -> int:
    # The scene's own arguments go last: the capturer stops reading at SCENE_ARGS.
    scene_args = [SCENE_ARGS, *args.forwarded] if getattr(args, "forwarded", None) else []
    engine_args = ["--path", ".", *godot_flags, capturer, "--", *user_args, *scene_args]
    verbose: bool = args.verbose
    print(f"[capture] godot {' '.join(engine_args)}", flush=True)
    result = run_godot(project, engine_args, timeout,
                       on_stdout=_echo(None if verbose else LIVE_TAGS), on_stderr=_echo(None) if verbose else None)
    if result.timed_out:
        print(f"[capture] ERROR: timed out after {timeout}s and was killed.", flush=True)
        return 1
    if result.returncode != 0:
        print(f"[capture] Godot exited with {result.returncode} ({result.elapsed:.1f}s):\n{result.output.rstrip()}", flush=True)
        return 1
    return 0


def _report(code: int, what: str) -> int:
    print(f"\n[SUCCESS] {what} saved (see the path above)." if code == 0 else f"\n[FAILED] {what} was not saved.", flush=True)
    return code


def _echo(tags: Optional[tuple]) -> Callable[[str], None]:
    def echo(line: str) -> None:
        if tags is None or any(tag in line for tag in tags):
            print("  " + line.rstrip("\n"), flush=True)
    return echo


def convert_avi_to_mp4(avi_path: Path, mp4_path: Path, keep_avi: bool = False, generate_gif: bool = False) -> Optional[Path]:
    """Converts a Godot MovieMaker AVI to an H.264 MP4 (and optional GIF) with FFmpeg."""
    if not avi_path.exists():
        print(f"[capture] AVI not found: {avi_path}", flush=True)
        return None
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        print(f"[capture] ffmpeg is not on PATH; kept the raw AVI: {avi_path}", flush=True)
        return avi_path
    mp4_path.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run([ffmpeg, "-y", "-i", str(avi_path), "-c:v", "libx264", "-pix_fmt", "yuv420p",
                             "-preset", "fast", "-crf", "22", str(mp4_path)], shell=False, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"[capture] FFmpeg failed; kept the raw AVI: {avi_path}\n{result.stderr[-2000:]}", flush=True)
        return avi_path
    if not keep_avi:
        try:
            os.remove(avi_path)
        except OSError:
            pass
    if generate_gif:
        gif = mp4_path.with_suffix(".gif")
        subprocess.run([ffmpeg, "-y", "-i", str(mp4_path), "-vf",
                        "fps=15,scale=640:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse", str(gif)],
                       shell=False, capture_output=True, text=True)
    return mp4_path
