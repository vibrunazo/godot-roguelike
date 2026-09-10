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

## 3. Testing & CLI Execution Policy (CRITICAL TIMEOUT RULES)

### Why Bare Commands Are Forbidden
Godot does not exit on GDScript compilation errors, cyclic preloads, or unhandled runtime exceptions. If an error occurs, Godot prints the error to the console, skips the rest of the function, and idles indefinitely. Because `--quit-after` only counts process frames after the engine initializes, scripts that fail to compile or hit missing autoloads will hang the terminal forever.

> **NEVER execute bare `godot --headless` commands directly under any circumstances.**
>
> All headless commands must run through an external OS watchdog that forcefully terminates the process after a hard timeout (60 seconds max).

### Approved Test Execution Commands

- **Run Full Test Suite (Preferred):**
  ```bash
  python run_tests.py
  ```

- **Run a Single Test Suite via Python Runner:**
  ```bash
  python run_tests.py test/test_combo_and_dash_cancel.tscn
  ```


- **Running Scratch / Diagnostic Scripts via Python One-Liner:**
  ```bash
  python -c "import subprocess; subprocess.run(['godot', '--headless', '--path', '.', '--quit-after', '60', '-s', 'scratch/my_script.gd'], timeout=10)"
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

