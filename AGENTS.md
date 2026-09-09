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
There are **12 automated test suites** in `test/*.tscn`. Every change must pass without errors (exit code 0).

- **Run a single test suite**:
  ```bash
  godot --headless --path . test/test_combo_and_dash_cancel.tscn
  ```
- **Run all 12 test suites (Python command)**:
  ```bash
  python -c "import subprocess, glob; [subprocess.run(f'godot --headless --path . {t}', shell=True, check=True) for t in sorted(glob.glob('test/*.tscn'))]; print('ALL 12 TESTS PASSED')"
  ```

---

## 4. Architecture & Key Patterns
- **State Machine**:
  - Located in `StateMachine/`. States extend `PlayerState` or `EnemyState`.
  - Transitions emit `finished.emit(next_state_name, data_dict)`.
- **Combat Components**:
  - `AttackComponent`: Sits under `ShapeCast3D`. Handles hit queries, damage dealing, screen shake, and `rehit_interval`.
  - `KnockbackComponent`: Handles physics impulse and exponential decay (`lerp` with `exp(-decay * delta)`). Active if magnitude > 1.0.
  - `HealthComponent`: Manages current/max health, damage taking, and `defeat` signal.
  - `WeaponSlot`: Extends `BoneAttachment3D`. Has exported `shapecast: ShapeCast3D`. Animating `WeaponSlot:enabled` automatically toggles `shapecast.enabled`.
- **Hit Timing & Multi-Hit Logic**:
  - `AttackComponent.rehit_interval`: Minimum interval (seconds) before a target can take damage again.
  - If `<= 0.0`, target is hit once per attack until `reset_exceptions()`.
  - If `> 0.0`, target exception is cleared after `rehit_interval` expires (used for SpinAttack).

---
