#!/usr/bin/env python3
"""Automated verification suite for the Capture System."""

import os
import subprocess
import sys


def test_map_capture() -> bool:
    print("\n--- Testing Map Screenshot Capture ---")
    out_file = "movies/test_verify_map.png"
    if os.path.exists(out_file):
        os.remove(out_file)

    cmd = [sys.executable, "capture.py", "map", "Levels/level_1.tscn", "--preset", "isometric", "--output", out_file]
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    print("STDOUT:\n", res.stdout)
    if res.returncode != 0:
        print("STDERR:\n", res.stderr)
        return False

    if not os.path.exists(out_file) or os.path.getsize(out_file) < 1000:
        print(f"FAILED: {out_file} was not generated or too small.")
        return False

    print(f"PASSED: Map screenshot verified ({os.path.getsize(out_file)} bytes)")
    return True


def test_anim_capture() -> bool:
    print("\n--- Testing Animation Video & GIF Capture ---")
    out_file = "movies/test_verify_brute.mp4"
    out_gif = "movies/test_verify_brute.gif"
    for f in [out_file, out_gif]:
        if os.path.exists(f):
            os.remove(f)

    cmd = [
        sys.executable,
        "capture.py",
        "anim",
        "Enemy/enemy_brute.tscn",
        "--state",
        "EnemyPunch",
        "--video",
        "--duration",
        "1.5",
        "--dummy",
        "--gif",
        "--output",
        out_file,
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=45)
    print("STDOUT:\n", res.stdout)
    if res.returncode != 0:
        print("STDERR:\n", res.stderr)
        return False

    if not os.path.exists(out_file) or os.path.getsize(out_file) < 1000:
        print(f"FAILED: {out_file} was not generated or too small.")
        return False

    if not os.path.exists(out_gif) or os.path.getsize(out_gif) < 1000:
        print(f"FAILED: {out_gif} was not generated.")
        return False

    print(f"PASSED: Anim video ({os.path.getsize(out_file)} bytes) & GIF ({os.path.getsize(out_gif)} bytes) verified")
    return True


def test_combat_scenario() -> bool:
    print("\n--- Testing Combat Scenario Staging ---")
    out_file = "movies/test_verify_combat.png"
    if os.path.exists(out_file):
        os.remove(out_file)

    cmd = [
        sys.executable,
        "capture.py",
        "combat",
        "--player",
        "--enemy",
        "brute",
        "--action",
        "enemy:state:EnemyPunch@10",
        "--action",
        f"screenshot:{out_file}@22",
        "--frames",
        "28",
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    print("STDOUT:\n", res.stdout)
    if res.returncode != 0:
        print("STDERR:\n", res.stderr)
        return False

    if not os.path.exists(out_file) or os.path.getsize(out_file) < 1000:
        print(f"FAILED: {out_file} was not generated.")
        return False

    print(f"PASSED: Combat scenario screenshot verified ({os.path.getsize(out_file)} bytes)")
    return True


def main() -> int:
    success = True
    success &= test_map_capture()
    success &= test_anim_capture()
    success &= test_combat_scenario()

    if success:
        print("\n============================================================")
        print("ALL CAPTURE SYSTEM VERIFICATION TESTS PASSED SUCCESSFULLY!")
        print("============================================================")
        return 0
    else:
        print("\nCAPTURE SYSTEM VERIFICATION FAILED.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
