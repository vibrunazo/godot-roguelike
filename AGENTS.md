# AGENT.md - Project Context & Guidelines

## 1. Project Overview
- **Engine**: Godot 4.7.2 stable official (Windows, Forward+ / D3D12).
- **Genre**: 3D Top-Down Action Roguelite (based on GameDev.tv Godot 3D Course, already completed).
- **Phase**: Adding custom gameplay improvements, combat polish, and balance.

---

## 2. Mandatory Coding Guidelines
1. **Strict GDScript Typing**:
   - `warnings/untyped_declaration=1` is enforced in `project.godot`.
   - Every variable, parameter, and function return type must be explicitly typed (e.g. `var x: float = 0.0`, `func foo(bar: int) -> void:`).
2. **Documentation Integrity**:
   - Preserve and maintain all docstrings (`## ...`) and comments on classes, exported variables, and functions.
3. **Git Commits**:
   - The user manages all git commits. **Never run `git commit` or `git push`**.

---

## 3. Testing Routine
Automated test suites reside in `test/*.tscn`. Every change must pass all test suites without errors (exit code 0).

- **Run all test suites (with per-test timeout guardrail & timing summary)**:
  ```bash
  python run_tests.py
  ```
- **Run a single test suite**:
  ```bash
  python run_tests.py test/test_combo_and_dash_cancel.tscn
  # or directly:
  godot --headless --path . test/test_combo_and_dash_cancel.tscn
  ```

---

## 4. Architecture & Key Patterns
- **State Machine**:
  - Located in `StateMachine/`. States extend `PlayerState` or `EnemyState`.
  - Transitions emit `finished.emit(next_state_name, data_dict)`.
- **Combat Components**:
  - `AttackComponent`: Sits under an `Area3D` hitbox or projectile. Listens to `body_entered` / `area_entered` signals to deal damage and knockback, handles screen shake, and manages `rehit_interval`.
  - `KnockbackComponent`: Handles physics impulse and exponential decay (`lerp` with `exp(-decay * delta)`). Active if magnitude > 1.0.
  - `HealthComponent`: Manages current/max health, damage taking, and `defeat` signal.
  - `WeaponSlot`: Extends `BoneAttachment3D`. Has exported `hitbox: Area3D`. Animating `WeaponSlot:enabled` automatically toggles `hitbox.monitoring` and `hitbox.monitorable`.
- **Hit Timing & Multi-Hit Logic**:
  - `AttackComponent.rehit_interval`: Minimum interval (seconds) before a target can take damage again.
  - If `<= 0.0`, target is hit once per attack until `reset_exceptions()`.
  - If `> 0.0`, target exception is cleared after `rehit_interval` expires (used for SpinAttack).

---


## Headless Godot Execution Rules

When writing scratch scripts or running verification tests via CLI:

1. **Always Use `--quit-after` as a Safety Rail:**
   Never run `godot --headless -s ...` bare. Always include `--quit-after <frames>` (e.g., `--quit-after 1` for static checks, or `--quit-after 120` for simulated physics). This forces Godot’s engine loop to terminate even if GDScript hits a fatal runtime error and bypasses `quit()`.
   * Example: `godot --headless --path . --quit-after 60 -s path/to/script.gd`

2. **Wrap Long-Running Tests in a Shell Timeout:**
   If a test requires indefinite frame stepping or signal awaits, do not invoke raw `godot`. Run it through a PowerShell timeout wrapper that force-kills the PID if it runs longer than 10 seconds:
   * `pwsh -Command "$p = Start-Process godot -ArgumentList '--headless','--path','.','-s','path/to/script.gd' -PassThru; if (-not $p.WaitForExit(10000)) { $p.Kill(); exit 1 } exit $p.ExitCode"`

3. **No Unchecked Node Lookups in `_init()`:**
   Standalone scripts extending `SceneTree` must use `get_node_or_null()` and guard clauses. Never chain method calls or property accessors on `find_child()` directly. If an asset is missing, log the error and call `quit(1)`.

4. **Always Include `timeout=<seconds>` in Python Test Runners:**
   When orchestrating test suites via Python `subprocess.run()`, always pass `timeout=20` (or appropriate per-test limit). If Godot encounters an unhandled runtime error or signal deadlock that bypasses `get_tree().quit()`, Python will automatically raise `subprocess.TimeoutExpired`, terminate the child process, and prevent the test runner from hanging indefinitely.