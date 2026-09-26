#!/usr/bin/env python3
"""Unified Capture & Recording Utility for Godot Maps, Animations, Combat Scenarios, and Tests.

Provides simple terminal CLI commands for agents and developers to:
1. Take screenshots or record videos of maps/levels from any angle.
2. Record videos or capture screenshots of character attacks, abilities, or raw animation assets.
3. Stage and record combat scenarios with players, enemies, and scripted actions.
4. Visually record existing and future test suites.

All output media is automatically saved to the movies/ folder.
MovieMaker AVI recordings are automatically converted to lightweight H.264 MP4s (and optional GIFs) via FFmpeg.

Usage Examples:
    # Map Screenshots & Video
    python capture.py map Levels/level_1.tscn --preset isometric
    python capture.py map Levels/level_1.tscn --preset all
    python capture.py map Levels/level_2.tscn --preset top_down --ortho
    python capture.py map Levels/level_1.tscn --video --duration 4.0

    # Animation & Character Recording
    python capture.py anim Enemy/enemy_brute.tscn --state EnemyPunch --screenshot --debug-collisions
    python capture.py anim Enemy/enemy_brute.tscn --state EnemyPunch --video --dummy
    python capture.py anim Enemy/melee_enemy.tscn --anim Melee_2H_Attack_Chop --video --dummy
    python capture.py anim Assets/KayKit_Assets/KayKit_Character_Animations_1.0/Animations/gltf/Rig_Medium/Animations/Melee_2H_Attack_Chop.res --video

    # Combat Scenario Staging
    python capture.py combat --player --enemy brute --action "enemy:state:EnemyPunch@15" --video
    python capture.py combat --scenario my_scenario.tscn --video

    # Test Suite Recording
    python capture.py test test/test_combo_and_dash_cancel.tscn --video
"""

import argparse
import os
import shutil
import subprocess
import sys
import threading
import time
from typing import List, Optional

from godot_env import resolve_godot


DEFAULT_TIMEOUT_SCREENSHOT = 25  # seconds
DEFAULT_TIMEOUT_VIDEO = 90       # seconds
OUTPUT_DIR = "movies"


def ensure_output_dir(path: str = OUTPUT_DIR) -> None:
    """Ensures the movies directory exists."""
    os.makedirs(path, exist_ok=True)


# Substring markers streamed live on stdout; everything else is kept for the
# end-of-run report (or streamed live with --verbose).
LIVE_TAGS = (
    "[MapCapturer]",
    "[AnimCapturer]",
    "[CombatScenario",
    "[TestCapturer]",
    "Saved screenshot",
    "Done recording",
)


def _pipe_reader(pipe, sink: List[str], stream_all: bool, tags) -> None:
    """Accumulates pipe lines and echoes them live: tagged lines, or all lines in verbose mode."""
    try:
        for line in iter(pipe.readline, ""):
            sink.append(line)
            if stream_all or any(tag in line for tag in tags):
                print(f"  {line}", end="" if line.endswith("\n") else "\n", flush=True)
    finally:
        try:
            pipe.close()
        except Exception:
            pass


def run_godot_command(
    godot_flags: List[str],
    user_args: List[str],
    scene_path: str,
    timeout: int = DEFAULT_TIMEOUT_SCREENSHOT,
    verbose: bool = False,
) -> subprocess.CompletedProcess:
    """Runs a Godot scene with the specified engine flags and user arguments using a timeout watchdog.

    Engine output streams live (highlight lines by default, everything with
    verbose=True) and is also accumulated so the CompletedProcess contract
    (returncode/stdout/stderr) is preserved for callers.
    """
    # OS-agnostic godot resolution (works on Linux, WSL, macOS, and Windows)
    godot_bin = resolve_godot()
    cmd: List[str] = [godot_bin, "--path", "."]
    cmd.extend(godot_flags)
    cmd.append(scene_path)
    if user_args:
        cmd.append("--")
        cmd.extend(user_args)

    print(f"[capture.py] Executing command: {' '.join(cmd)}")
    t0 = time.time()
    try:
        proc = subprocess.Popen(
            cmd,
            shell=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except Exception as e:
        print(f"[capture.py] ERROR: Failed to execute Godot: {e}")
        sys.exit(1)
    stdout_lines: List[str] = []
    stderr_lines: List[str] = []
    readers = [
        threading.Thread(target=_pipe_reader, args=(proc.stdout, stdout_lines, verbose, LIVE_TAGS)),
        threading.Thread(target=_pipe_reader, args=(proc.stderr, stderr_lines, verbose, ())),
    ]
    for reader in readers:
        reader.start()
    try:
        returncode = proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        elapsed = time.time() - t0
        print(f"[capture.py] ERROR: Godot command timed out after {timeout} seconds and was terminated.")
        proc.kill()
        proc.wait()
        for reader in readers:
            reader.join(timeout=5)
        sys.exit(1)
    for reader in readers:
        reader.join(timeout=10)
    elapsed = time.time() - t0
    res = subprocess.CompletedProcess(cmd, returncode, "".join(stdout_lines), "".join(stderr_lines))
    if res.returncode != 0:
        print(f"[capture.py] Process exited with error code {res.returncode} ({elapsed:.2f}s):")
        if res.stdout:
            print(res.stdout)
        if res.stderr:
            print(res.stderr)
    else:
        print(f"[capture.py] Godot execution completed successfully in {elapsed:.2f}s")
    return res


def convert_avi_to_mp4(avi_path: str, mp4_path: str, keep_avi: bool = False, generate_gif: bool = False) -> Optional[str]:
    """Converts a Godot MovieMaker AVI to a high-compatibility H.264 MP4 via FFmpeg."""
    if not os.path.exists(avi_path):
        print(f"[capture.py] Warning: AVI file not found for conversion: {avi_path}")
        return None

    avi_size_mb = os.path.getsize(avi_path) / (1024 * 1024)
    print(f"[capture.py] Converting raw AVI ({avi_size_mb:.1f} MB) -> MP4: {mp4_path}")

    ffmpeg_bin = shutil.which("ffmpeg")
    if not ffmpeg_bin:
        print("[capture.py] Warning: ffmpeg not found on PATH. Raw AVI kept at: " + avi_path)
        return avi_path

    # FFmpeg command: H.264 video, yuv420p pixel format for universal compatibility
    cmd = [
        ffmpeg_bin,
        "-y",
        "-i", avi_path,
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-preset", "fast",
        "-crf", "22",
        mp4_path,
    ]

    res = subprocess.run(cmd, shell=False, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[capture.py] FFmpeg conversion failed: {res.stderr}")
        return avi_path

    mp4_size_mb = os.path.getsize(mp4_path) / (1024 * 1024)
    print(f"[capture.py] MP4 created successfully: {mp4_path} ({mp4_size_mb:.2f} MB)")

    if not keep_avi:
        try:
            os.remove(avi_path)
        except OSError:
            pass

    # Optional GIF generation
    if generate_gif:
        gif_path = os.path.splitext(mp4_path)[0] + ".gif"
        print(f"[capture.py] Generating high-quality GIF: {gif_path}")
        gif_cmd = [
            ffmpeg_bin,
            "-y",
            "-i", mp4_path,
            "-vf", "fps=15,scale=640:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse",
            gif_path,
        ]
        gif_res = subprocess.run(gif_cmd, shell=False, capture_output=True, text=True)
        if gif_res.returncode == 0:
            print(f"[capture.py] GIF created: {gif_path}")

    return mp4_path


# -----------------------------------------------------------------------------
# SUBCOMMAND HANDLERS
# -----------------------------------------------------------------------------

def handle_map(args: argparse.Namespace) -> int:
    """Handles map / level capture."""
    ensure_output_dir()
    level_path = args.level
    is_video = args.video

    godot_flags: List[str] = []
    user_args: List[str] = [f"--level={level_path}"]

    if args.preset:
        user_args.append(f"--preset={args.preset}")
    if args.cam_pos:
        user_args.append(f"--cam-pos={args.cam_pos}")
    if args.cam_target:
        user_args.append(f"--cam-target={args.cam_target}")
    if args.target_node:
        user_args.append(f"--target-node={args.target_node}")
    if args.cam_fov:
        user_args.append(f"--cam-fov={args.cam_fov}")
    if args.cam_dist:
        user_args.append(f"--cam-dist={args.cam_dist}")
    if args.cam_height:
        user_args.append(f"--cam-height={args.cam_height}")
    if args.cam_size:
        user_args.append(f"--cam-size={args.cam_size}")
    if args.ortho:
        user_args.append("--cam-ortho")
    if args.debug_collisions:
        user_args.append("--debug-collisions")
    if args.freeze:
        user_args.append("--freeze")
    if getattr(args, "show_ui", False):
        user_args.append("--show-ui")
    else:
        user_args.append("--hide-ui")

    level_name = os.path.splitext(os.path.basename(level_path))[0]
    timeout = DEFAULT_TIMEOUT_SCREENSHOT

    if is_video:
        timeout = DEFAULT_TIMEOUT_VIDEO
        duration = args.duration if args.duration else 3.0
        user_args.append("--video")
        user_args.append(f"--duration={duration}")

        temp_avi = os.path.join(OUTPUT_DIR, f"temp_{level_name}_{int(time.time())}.avi")
        godot_flags.extend(["--write-movie", temp_avi])

        out_mp4 = args.output if args.output else os.path.join(OUTPUT_DIR, f"{level_name}_{args.preset or 'isometric'}.mp4")
        if not out_mp4.endswith(".mp4"):
            out_mp4 += ".mp4"

        res = run_godot_command(godot_flags, user_args, "tools/capture/map_capturer.tscn", timeout=timeout, verbose=getattr(args, "verbose", False))
        if res.returncode == 0:
            final_media = convert_avi_to_mp4(temp_avi, out_mp4, keep_avi=args.keep_avi, generate_gif=args.gif)
            print(f"\n[SUCCESS] Level video saved: {final_media}")
            return 0
        return 1
    else:
        out_png = args.output
        if out_png:
            user_args.append(f"--output={out_png}")
        res = run_godot_command(godot_flags, user_args, "tools/capture/map_capturer.tscn", timeout=timeout, verbose=getattr(args, "verbose", False))
        if res.returncode == 0:
            if args.preset == "all":
                print(f"\n[SUCCESS] All preset angles saved to {OUTPUT_DIR}/")
            else:
                target_file = out_png if out_png else os.path.join(OUTPUT_DIR, f"{level_name}_{args.preset or 'isometric'}.png")
                print(f"\n[SUCCESS] Level screenshot saved: {target_file}")
            return 0
        return 1


def handle_anim(args: argparse.Namespace) -> int:
    """Handles character, enemy, or raw animation asset capture."""
    ensure_output_dir()
    target_path = args.target
    is_video = args.video

    godot_flags: List[str] = []
    user_args: List[str] = [f"--target={target_path}"]

    if args.anim:
        user_args.append(f"--anim={args.anim}")
    if args.state:
        user_args.append(f"--state={args.state}")
    if args.rig:
        user_args.append(f"--rig={args.rig}")
    if args.cam_angle:
        user_args.append(f"--cam-angle={args.cam_angle}")
    if getattr(args, "cam_dist", None):
        user_args.append(f"--cam-dist={args.cam_dist}")
    if getattr(args, "cam_height", None):
        user_args.append(f"--cam-height={args.cam_height}")
    if getattr(args, "cam_fov", None):
        user_args.append(f"--cam-fov={args.cam_fov}")
    if args.speed:
        user_args.append(f"--speed={args.speed}")
    if args.time is not None:
        user_args.append(f"--time={args.time}")
    if args.dummy:
        user_args.append("--dummy")
    if args.debug_collisions:
        user_args.append("--debug-collisions")
    if getattr(args, "show_ui", False):
        user_args.append("--show-ui")
    else:
        user_args.append("--hide-ui")

    base_name = os.path.splitext(os.path.basename(target_path))[0]
    tag = args.anim or args.state or "preview"
    tag = os.path.splitext(os.path.basename(tag))[0]

    if is_video:
        timeout = DEFAULT_TIMEOUT_VIDEO
        duration = args.duration if args.duration else 2.5
        user_args.append("--video")
        user_args.append(f"--duration={duration}")

        temp_avi = os.path.join(OUTPUT_DIR, f"temp_{base_name}_{tag}_{int(time.time())}.avi")
        godot_flags.extend(["--write-movie", temp_avi])

        out_mp4 = args.output if args.output else os.path.join(OUTPUT_DIR, f"{base_name}_{tag}.mp4")
        if not out_mp4.endswith(".mp4"):
            out_mp4 += ".mp4"

        res = run_godot_command(godot_flags, user_args, "tools/capture/anim_capturer.tscn", timeout=timeout, verbose=getattr(args, "verbose", False))
        if res.returncode == 0:
            final_media = convert_avi_to_mp4(temp_avi, out_mp4, keep_avi=args.keep_avi, generate_gif=args.gif)
            print(f"\n[SUCCESS] Animation video saved: {final_media}")
            return 0
        return 1
    else:
        out_png = args.output
        if out_png:
            user_args.append(f"--output={out_png}")
        else:
            out_png = os.path.join(OUTPUT_DIR, f"{base_name}_{tag}_{args.cam_angle or 'three_quarters'}.png")
            user_args.append(f"--output={out_png}")

        res = run_godot_command(godot_flags, user_args, "tools/capture/anim_capturer.tscn", timeout=DEFAULT_TIMEOUT_SCREENSHOT, verbose=getattr(args, "verbose", False))
        if res.returncode == 0:
            print(f"\n[SUCCESS] Animation screenshot saved: {out_png}")
            return 0
        return 1


COMBAT_ENEMIES = ("brute", "melee", "ranged", "firebomber", "thunder_mage")


def _combat_tag(enemy: Optional[str]) -> str:
    """Derives a filename tag from --enemy: registry name, scene basename, or 'combat'."""
    if not enemy:
        return "combat"
    if enemy.lower() in COMBAT_ENEMIES:
        return enemy.lower()
    base = os.path.basename(enemy)
    if base.lower().endswith(".tscn"):
        base = base[:-5]
    return base or "combat"


def _avi_name(output: Optional[str], fallback_prefix: str) -> str:
    """Names the raw MovieMaker AVI after --output when given, else a timestamped temp name."""
    if output:
        base = os.path.splitext(os.path.basename(output))[0] or fallback_prefix
        return f"{base}.avi"
    return f"{fallback_prefix}_{int(time.time())}.avi"


def handle_combat(args: argparse.Namespace) -> int:
    """Handles combat scenario testbed staging and recording."""
    ensure_output_dir()
    scene_file = args.scenario if args.scenario else "tools/capture/combat_scenario_template.tscn"
    is_video = args.video

    godot_flags: List[str] = []
    user_args: List[str] = []

    if args.player:
        user_args.append("--player")
    if args.enemy:
        enemy_id = args.enemy
        if enemy_id.lower() not in COMBAT_ENEMIES:
            scene_path = enemy_id[len("res://"):] if enemy_id.startswith("res://") else enemy_id.lstrip("./")
            if not scene_path.lower().endswith(".tscn"):
                scene_path += ".tscn"
            if not os.path.exists(scene_path):
                print(f"[capture.py] ERROR: Unknown --enemy '{enemy_id}'. Use a registry name {list(COMBAT_ENEMIES)} or a scene path (e.g. Enemy/akira_boss.tscn).")
                return 1
        user_args.append(f"--enemy={args.enemy}")
    if args.action:
        for act in args.action:
            user_args.append(f"--action={act}")
    if args.no_debug_collisions:
        user_args.append("--no-debug-collisions")
    if getattr(args, "debug_collisions", False):
        user_args.append("--debug-collisions")
    if getattr(args, "enable_ai", False):
        user_args.append("--enable-ai")
    if getattr(args, "freeze", False):
        user_args.append("--freeze")
    if getattr(args, "player_pos", None):
        user_args.append(f"--player-pos={args.player_pos}")
    if getattr(args, "enemy_pos", None):
        user_args.append(f"--enemy-pos={args.enemy_pos}")
    if getattr(args, "cam_pos", None):
        user_args.append(f"--cam-pos={args.cam_pos}")
    if getattr(args, "cam_target", None):
        user_args.append(f"--cam-target={args.cam_target}")
    if getattr(args, "cam_fov", None):
        user_args.append(f"--cam-fov={args.cam_fov}")
    if getattr(args, "show_ui", False):
        user_args.append("--show-ui")
    else:
        user_args.append("--hide-ui")

    tag = _combat_tag(args.enemy)
    if is_video:
        timeout = DEFAULT_TIMEOUT_VIDEO
        duration = args.duration if args.duration else 3.0
        user_args.append("--video")
        user_args.append(f"--duration={duration}")

        temp_avi = os.path.join(OUTPUT_DIR, _avi_name(args.output, f"temp_combat_{tag}"))
        godot_flags.extend(["--write-movie", temp_avi])

        out_mp4 = args.output if args.output else os.path.join(OUTPUT_DIR, f"combat_{tag}.mp4")
        if not out_mp4.endswith(".mp4"):
            out_mp4 += ".mp4"

        res = run_godot_command(godot_flags, user_args, scene_file, timeout=timeout, verbose=getattr(args, "verbose", False))
        if res.returncode == 0:
            final_media = convert_avi_to_mp4(temp_avi, out_mp4, keep_avi=args.keep_avi, generate_gif=args.gif)
            print(f"\n[SUCCESS] Combat scenario video saved: {final_media}")
            return 0
        return 1
    else:
        out_png = args.output if args.output else os.path.join(OUTPUT_DIR, f"combat_{tag}.png")
        if not out_png.endswith(".png"):
            out_png += ".png"
        user_args.append(f"--output={out_png}")
        if args.frames:
            user_args.append(f"--frames={args.frames}")

        res = run_godot_command(godot_flags, user_args, scene_file, timeout=DEFAULT_TIMEOUT_SCREENSHOT, verbose=getattr(args, "verbose", False))
        if res.returncode == 0:
            print(f"\n[SUCCESS] Combat scenario screenshot saved: {out_png}")
            return 0
        return 1


def handle_test(args: argparse.Namespace) -> int:
    """Handles running and visually recording test scenes."""
    ensure_output_dir()
    test_path = args.test
    is_video = args.video or True  # Default to video for tests unless screenshot explicitly requested

    test_name = os.path.splitext(os.path.basename(test_path))[0]
    godot_flags: List[str] = []
    user_args: List[str] = [f"--test={test_path}"]

    if args.no_debug_collisions:
        user_args.append("--no-debug-collisions")
    if getattr(args, "show_ui", False):
        user_args.append("--show-ui")
    else:
        user_args.append("--hide-ui")

    timeout = DEFAULT_TIMEOUT_VIDEO
    duration = args.duration if args.duration else 5.0
    user_args.append("--video")
    user_args.append(f"--duration={duration}")

    temp_avi = os.path.join(OUTPUT_DIR, _avi_name(args.output, f"temp_test_{test_name}"))
    godot_flags.extend(["--write-movie", temp_avi])

    out_mp4 = args.output if args.output else os.path.join(OUTPUT_DIR, f"{test_name}.mp4")
    if not out_mp4.endswith(".mp4"):
        out_mp4 += ".mp4"

    res = run_godot_command(godot_flags, user_args, "tools/capture/test_capturer.tscn", timeout=timeout, verbose=getattr(args, "verbose", False))
    if res.returncode == 0:
        final_media = convert_avi_to_mp4(temp_avi, out_mp4, keep_avi=args.keep_avi, generate_gif=args.gif)
        print(f"\n[SUCCESS] Test execution video saved: {final_media}")
        return 0
    return 1


# -----------------------------------------------------------------------------
# MAIN CLI ENTRYPOINT
# -----------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Capture screenshots and record videos of Godot levels, animations, combat, and tests."
    )
    subparsers = parser.add_subparsers(dest="subcommand", required=True, help="Subcommand to run")

    # --- MAP SUBCOMMAND ---
    p_map = subparsers.add_parser("map", help="Capture map/level screenshots or video")
    p_map.add_argument("level", help="Path to level scene (e.g. Levels/level_1.tscn)")
    p_map.add_argument("--preset", choices=["isometric", "top_down", "front", "side", "overview", "all"], default="isometric", help="Camera preset angle")
    p_map.add_argument("--cam-pos", help="Custom camera position as X,Y,Z")
    p_map.add_argument("--cam-target", help="Custom camera look-at target as X,Y,Z")
    p_map.add_argument("--target-node", help="Node name to frame (e.g. Player, ExitPoint)")
    p_map.add_argument("--cam-fov", type=float, help="Camera FOV in degrees")
    p_map.add_argument("--cam-dist", type=float, help="Camera distance multiplier")
    p_map.add_argument("--cam-height", type=float, help="Camera height offset")
    p_map.add_argument("--cam-size", type=float, help="Orthographic camera size")
    p_map.add_argument("--ortho", action="store_true", help="Use orthographic camera projection")
    p_map.add_argument("--debug-collisions", action="store_true", help="Render collision shapes and hitboxes")
    p_map.add_argument("--freeze", action="store_true", help="Freeze AI and character physics")
    p_map.add_argument("--show-ui", action="store_true", help="Keep UI overlays and banners visible (suppressed by default)")
    p_map.add_argument("--video", action="store_true", help="Record video instead of screenshot")
    p_map.add_argument("--duration", type=float, help="Video duration in seconds")
    p_map.add_argument("--output", help="Output file path in movies/")
    p_map.add_argument("--keep-avi", action="store_true", help="Do not delete intermediate AVI file")
    p_map.add_argument("--gif", action="store_true", help="Also generate an animated GIF")
    p_map.add_argument("--verbose", action="store_true", help="Stream full engine output live instead of highlight lines")

    # --- ANIM SUBCOMMAND ---
    p_anim = subparsers.add_parser("anim", help="Capture or record character animations or raw assets")
    p_anim.add_argument("target", help="Path to character scene (.tscn), animation resource (.res), or GLB archive (.glb)")
    p_anim.add_argument("--anim", help="Animation name to play")
    p_anim.add_argument("--state", help="StateMachine state to request (e.g. EnemyPunch, AISlam)")
    p_anim.add_argument("--rig", help="Base model GLB for raw .res animations")
    p_anim.add_argument("--cam-angle", choices=["three_quarters", "front", "side", "top_down"], default="three_quarters", help="Camera angle")
    p_anim.add_argument("--cam-dist", type=float, help="Camera distance multiplier relative to default")
    p_anim.add_argument("--cam-height", type=float, help="Camera height offset")
    p_anim.add_argument("--cam-fov", type=float, help="Camera field of view in degrees")
    p_anim.add_argument("--dummy", action="store_true", help="Spawn target dummy in attack strike zone")
    p_anim.add_argument("--speed", type=float, default=1.0, help="Playback speed scale (e.g. 0.5 for slow-mo)")
    p_anim.add_argument("--time", type=float, help="Screenshot timestamp in seconds")
    p_anim.add_argument("--debug-collisions", action="store_true", help="Render collision shapes and hitboxes")
    p_anim.add_argument("--show-ui", action="store_true", help="Keep UI overlays and banners visible (suppressed by default)")
    p_anim.add_argument("--video", action="store_true", help="Record video instead of screenshot")
    p_anim.add_argument("--duration", type=float, help="Video duration in seconds")
    p_anim.add_argument("--output", help="Output file path in movies/")
    p_anim.add_argument("--keep-avi", action="store_true", help="Do not delete intermediate AVI file")
    p_anim.add_argument("--gif", action="store_true", help="Also generate an animated GIF")
    p_anim.add_argument("--verbose", action="store_true", help="Stream full engine output live instead of highlight lines")

    # --- COMBAT SUBCOMMAND ---
    p_combat = subparsers.add_parser("combat", help="Stage and record custom combat scenarios")
    p_combat.add_argument("--scenario", help="Path to custom scenario script or scene")
    p_combat.add_argument("--player", action="store_true", help="Spawn player character")
    p_combat.add_argument("--enemy", help="Spawn enemy character: registry name (brute, melee, ranged, firebomber, thunder_mage) or scene path (e.g. Enemy/akira_boss.tscn)")
    p_combat.add_argument("--action", action="append", help="Scheduled action: target:type:param@frame")
    p_combat.add_argument("--no-debug-collisions", action="store_true", help="Disable collision debug shapes")
    p_combat.add_argument("--debug-collisions", action="store_true", help="Enable collision debug shapes")
    p_combat.add_argument("--enable-ai", action="store_true", help="Enable autonomous AI processing")
    p_combat.add_argument("--freeze", action="store_true", help="Hold staged combatants in place (AI and character physics paused)")
    p_combat.add_argument("--player-pos", help="Player spawn position X,Y,Z (e.g. 0.0,1.0,4.0)")
    p_combat.add_argument("--enemy-pos", help="Enemy spawn position X,Y,Z (e.g. 0.0,1.0,0.0)")
    p_combat.add_argument("--cam-pos", help="Camera position X,Y,Z (e.g. 5.5,2.2,0.5)")
    p_combat.add_argument("--cam-target", help="Camera look-at target X,Y,Z (e.g. 0.0,1.0,0.5)")
    p_combat.add_argument("--cam-fov", type=float, help="Camera field of view")
    p_combat.add_argument("--show-ui", action="store_true", help="Keep UI overlays and banners visible (suppressed by default)")
    p_combat.add_argument("--frames", type=int, help="Frames to run before screenshot")
    p_combat.add_argument("--video", action="store_true", help="Record video")
    p_combat.add_argument("--duration", type=float, help="Video duration in seconds")
    p_combat.add_argument("--output", help="Output file path in movies/")
    p_combat.add_argument("--keep-avi", action="store_true", help="Do not delete intermediate AVI file")
    p_combat.add_argument("--gif", action="store_true", help="Also generate an animated GIF")
    p_combat.add_argument("--verbose", action="store_true", help="Stream full engine output live instead of highlight lines")

    # --- TEST SUBCOMMAND ---
    p_test = subparsers.add_parser("test", help="Visually record a test suite execution")
    p_test.add_argument("test", help="Path to test scene (e.g. test/test_combo_and_dash_cancel.tscn)")
    p_test.add_argument("--video", action="store_true", default=True, help="Record test as video")
    p_test.add_argument("--duration", type=float, default=5.0, help="Max test duration in seconds")
    p_test.add_argument("--no-debug-collisions", action="store_true", help="Disable collision debug shapes")
    p_test.add_argument("--show-ui", action="store_true", help="Keep UI overlays and banners visible (suppressed by default)")
    p_test.add_argument("--output", help="Output file path in movies/")
    p_test.add_argument("--keep-avi", action="store_true", help="Do not delete intermediate AVI file")
    p_test.add_argument("--gif", action="store_true", help="Also generate an animated GIF")
    p_test.add_argument("--verbose", action="store_true", help="Stream full engine output live instead of highlight lines")

    args = parser.parse_args()

    if args.subcommand == "map":
        return handle_map(args)
    elif args.subcommand == "anim":
        return handle_anim(args)
    elif args.subcommand == "combat":
        return handle_combat(args)
    elif args.subcommand == "test":
        return handle_test(args)

    return 0


if __name__ == "__main__":
    sys.exit(main())
