# Plan: active abilities, spell books and the Fireball (revision 3)

Status: **implemented** (2026-09-30). The follow-ups are TODO item 8.

## As built: where the code differs from this plan

- **Gravity is optional, and an action never switches to the fall state.**
  `CharacterAction` applies gravity while the action runs and keeps running
  it. A new export, `float_in_air`, holds the height instead (for air combos;
  the dash, a separate state, still floats). Nothing transitions to
  `fall_state` mid-action.
- **States opt in to casting.** `CharacterState.check_ability()` casts only
  where `_allows_ability()` says so: the `allows_abilities` export (set on
  `PlayerRun`), `cancelable` for timed actions, and "released and cancelable"
  for a cast. Without it, pressing a key during a dash cast at once, because
  the input component drives the current state's check directly.
- **Before release, a jump cannot cancel a cast either**, only a dash can.
- **Pickups are children of the `ItemSpawner`**, so they leave with their
  level, not through `VfxManager.spawn_world_entity()`.
- **No `test_item_spawner` suite.** The item checks run in
  `test_level_rotation_nav`, which already loads every level: the items rest
  on the floor and a path reaches them from the spawn.
- **Floating messages reuse the damage-number popup**
  (`VfxManager.spawn_floating_text()`).
- **`EnemyProjectile` became `Projectile`.** Its scene is now
  `Enemy/fireball_projectile.tscn`, and `GlobalVars.enemy_projectile_scene`
  became `default_projectile_scene`.
- **Gear with full slots** skips its ability with a warning in the log (no
  popup yet; see TODO item 8).
- **Learning an ability that gear grants makes it permanent in its slot**
  (its source becomes null), so a book for it is still offered and useful.
- **`ItemSpawner` waits for its own level's navmesh:** the map's closest
  point to the player must belong to the `navigation_region` export. The
  boss arena sets `count = 0`, so no items spawn there.

The plan below is kept as written.

Changes since revision 2 (from the review):
- **Cast state base.** `CharacterAttack` is split in two. A shared base,
  `CharacterAction`, holds what attacks and casts have in common, and it now
  applies gravity. `CharacterAttack` keeps only the melee parts.
  `AbilityCastState` extends `CharacterAction`, not `CharacterAttack`.
- **When the player can cast** is decided by the current body state. The
  ability key raises a request, like the attack, dash and jump keys already
  do, and the state checks it. Checking `can_accept_order()` would have let
  a cast cut into any swing, dash or jump.
- **Items teach through a hook that gear overrides**, so equipping gear
  never teaches its abilities for good.
- **Ability slots are fixed state nodes**, wired in the scene. Nothing is
  created at runtime, and the AI points at a slot through the existing typed
  `body_state` export.

## 1. Goals

- Active abilities are **data**: one `AbilityResource` file per ability.
  Balance lives in `.tres` files and scenes.
- Any `Character` (the player or an enemy) holds abilities in **N slots**.
  The count is set by how many slot states the scene wires; the player has 4.
- Abilities come from:
  - **defaults** set on a character;
  - **items**: a book teaches an ability for good, and gear grants one while
    equipped (e.g. a future laser-eyes helm);
  - the **shop**, which sells the same items.
- The player casts with the `InputMap` actions `ability_1`..`ability_4`,
  bound to the keys 1–4.
- The first ability is **Fireball**, built on the ranged enemies' fireball
  projectile. The run's first level spawns the *"Fireball for Dummies"* book,
  only because it is the one item in the level spawn pool.

## 2. Reuse map: what is new and what is not

| Need | Reused as it is / extended | New |
|---|---|---|
| Cooldown, tag gates, aim + auto-aim, animation and return to run, cancel windows, `is_attacking`, lifecycle events | **extracted** from `CharacterAttack` into `CharacterAction` | `AbilityCastState` adds only release, cost and the slot's ability |
| When the player may cast | the request pattern that attack, dash and jump already use (`command_*`, then `check_*` in body states), plus the `dash_cancel` cancel window | `ability_requested` + `CharacterState.check_ability()` |
| AI casting | `AIConditionalAttack` / `AIAttack` with `body_state` set to a slot state | none |
| Holding granted abilities, grant and revoke bookkeeping | `PassiveAbilityComponent`, **renamed and extended** into the `AbilitySystemComponent` | the active ability slots |
| What happens at release | **projectile and payload scenes** (damage, damage type, burn, knockback all live there today), `PayloadPropertyOverride` for per-ability tuning, `GameplayEffect` for self-buffs | a shared payload spawn function, **extracted** from the code duplicated in `ProjectileSpawnerComponent` and `PayloadPassiveAbility` |
| Damage math | `AttackComponent` inside the projectile scene; the existing `damage * get_damage_modifier()` scaling from `PayloadPassiveAbility` | none |
| Lifecycle hooks for upgrades | `AbilityEvent` + passives | none |
| Books and ability gear | `ItemResource`, `GearItemResource.attach()`/`unequip()`, `EquipmentComponent.apply_item()`, `pending_items` | a `granted_abilities` field + one hook |
| Keeping abilities through the run | `ProgressionState.bind_player()`, which already restores gear and health | a learned-abilities record |
| Which items can be offered | the shop's stock filter | moved into `ProgressionState` and shared by the shop and level spawns |

## 3. CharacterAction: the shared base extracted from CharacterAttack

`CharacterAttack` has about 470 lines today. Roughly half of them apply to any
timed action, and the other half are melee only. Split it:

- **`CharacterAction extends CharacterState`** (`StateMachine/character_action.gd`)
  holds the shared half, **moved** rather than copied:
  - the cooldown (`cooldown`, `starting_cooldown`, ticking, `is_on_cooldown()`),
    the tag gates (`required_tags`, `blocked_tags`, `start_cooldown_on_enabled`)
    and `can_activate()`;
  - `movement_speed`, `uninterruptable` and `is_uninterruptable()`;
  - the animation (`attack_animation_name`, `change_immediate()`, and
    `next_states` when the animation finishes);
  - the aim (`_resolve_aim()` snapshot, `_aim_at_current_target()`, and
    `is_attacking` on while it runs, so the auto-aim target stays locked);
  - **the cancel window:** `check_dash()`, `check_jump()` and the new
    `check_ability()` are all gated by one export. Rename `dash_cancel` →
    `cancelable`, since it now gates three cancels, and update every scene
    that sets it.
  - the lifecycle events: STARTED on enter, ENDED on exit. **ENDED is sent
    once**, carrying `{"completed": ...}` from a virtual `_is_completed()`, so
    subclasses never send a second one;
  - **movement with gravity:** it applies gravity to `velocity.y` instead of
    zeroing it, and goes to `fall_state` when the body leaves the floor, the
    same way `core_movement()` does. The per-subclass horizontal velocity
    stays a virtual (lunge, hitstop).
- **`CharacterAttack extends CharacterAction`** keeps only the melee parts:
  weapon slot and `AttackComponent` setup, the combo queue (`combo_next`,
  `queued_attack_time`, `check_attack()` queueing), the lunge and its landing
  assist, attacker hitstop, the ACTIVE event on the weapon's `slash`, and
  `damage`, `knockback`, `rehit_interval` and `effects_to_apply`.
- **This changes melee behavior on purpose.** Attacks now fall off ledges
  instead of hovering: today `physics_update()` sets the velocity from
  `move_direction`, whose Y is 0, and never uses `fall_state`. Phase 1 first
  confirms with a scratch script that a melee attack or lunge off a ledge
  hovers today. The lunge's landing assist already steers away from pits, so
  most lunges are unaffected.
- The subclasses of `CharacterAttack` (Akira boss attacks,
  `GroundSlamAttack`, `PlayerJumpKick`, ...) stay on `CharacterAttack` unless
  they don't use melee parts; each is checked during the split.

## 4. AbilityCastState extends CharacterAction (`Abilities/ability_cast_state.gd`)

One node per **slot**, placed in the character's body `StateMachine` in the
scene (`AbilitySlot1`..`AbilitySlot4` on the player). Each slot node's own
exports are wired in the scene: `character`, `fall_state`, `dash_state`,
`jump_state`, `next_states` (the return state) and `cast_origin`.

- `ability: AbilityResource` (null = empty slot). It is set by the ASC.
  `set_ability()` copies the resource into the `CharacterAction` fields:
  animation, movement speed, cooldown and starting cooldown, tags,
  `cancelable`, `uninterruptable`. Clearing the slot resets them.
- `can_activate()`: false for an empty slot; otherwise `super()` plus the pool
  cost check.
- `enter()`: an empty slot goes straight back to its return state. Otherwise
  `super()` handles the animation, the aim, the cooldown and STARTED. It then
  pays the cost and starts the `release_time` timer on the physics clock.
- **Release:**
  - The direction points at `current_target` when valid; otherwise it is the
    snapshotted aim, normalized.
  - It calls `PayloadSpawner.spawn()` from `cast_origin` and applies
    `caster_effects`.
  - It broadcasts ACTIVE and emits the ASC's `ability_cast`.
- **Committing:** until release, `accepts_orders()` returns false and
  `check_ability()` refuses, so neither another ability nor an AI order can
  cut into it. A dash can, when `cancelable` is set.
- `_is_completed()` returns `_released`.
- The cooldown lives in the slot state, like every attack's. A slot keeps its
  cooldown while its ability stays; granting a new ability resets it.

## 5. When the player can cast

The ability key works like the attack, dash and jump keys already do:
- `PlayerInputComponent.order_ability(slot)` refreshes the aim, sets
  `character.ability_requested = slot` (`-1` = none) and drives the current
  body state's `check_ability()` immediately, as `order_attack()` does.
- `CharacterState.check_ability()` consumes the request. If the slot's state
  `can_activate()`, it calls `request_state()` on it.
- **Which states check it decides where casting is allowed:**
  - `PlayerRun` checks it.
  - `CharacterAction` checks it only when `cancelable` allows. Melee attacks
    therefore allow a cast in the same window as a dash, and casts refuse
    until release.
  - `PlayerDash`, `PlayerJump`, `PlayerFall` and stun don't check it. There is
    no casting while dashing, jumping or falling, and no special
    `is_on_floor()` rule.
  - Allowing an air cast later means a jump state that calls `check_ability()`.
- The request follows the existing intent rules: consumed on read, dropped on
  every transition (`StateMachine._clear_stale_intents()`) and cleared by
  `Character._clear_intents_and_motion()`.
- The AI keeps ordering through `can_accept_order()`, as it does for every
  enemy attack today.

## 6. AbilitySystemComponent (ASC)

It is `PassiveAbilityComponent`, renamed (`Components/ability_system_component.gd`)
and extended. As in UE5 GAS, **one component owns every ability the character
has**, passive and active. `AttributeComponent` keeps attributes, effects and
tags; merging those in too would be a separate refactor.

- **The rename is a hard cut:**
  - `Character.passive_ability_component` → `ability_system_component`
    (typed export);
  - the node in `player.tscn` is renamed;
  - `GearItemResource`, `Character.broadcast_ability_event`, `PassiveAbility`
    and `test_passive_abilities` are updated.
- **Its passive half is unchanged:** `add_passive()`, `remove_passive()`,
  `notify_ability_event()`, and so on.
- **New active half:**
  - `slots: Array[AbilityCastState]`: typed exports to the scene's slot
    states. **The slot count is `slots.size()`.**
  - `starting_abilities: Array[AbilityResource]` (indexed by slot, null =
    empty): the defaults for the player or an enemy.
  - **Granting and revoking:**
    - `grant_ability(ability, source: Object = null, slot := -1) -> int`
      returns the slot, or -1 when the ability is already held or no slot is
      free. `source` records who granted it, as in GAS: null means learned
      for good; a gear item means granted while that gear is equipped.
    - `revoke_ability(slot)` and `revoke_abilities_from(source)`. If the slot
      is mid-cast, the body goes home first.
  - **Queries:** `get_ability(slot)`, `has_ability(ability)`,
    `has_free_slot()`, `get_learned_abilities()` (source == null, for the run
    record), `set_learned_abilities(slots)`, `get_cooldown_fraction(slot)`
    (for the HUD).
  - **Signals:** `ability_granted(slot, ability, source)`,
    `ability_revoked(slot, ability)`, `ability_cast(slot, ability)`.
- **Loud failures:** it `push_error`s when an ability's `cast_animation` is not
  a state in the character's AnimationTree, or when a slot has no
  `cast_origin`.

## 7. AbilityResource (`Abilities/ability_resource.gd`)

Pure data, named after the `ItemResource`/`EnemyResource`/`DungeonResource`
convention. It has no damage fields: damage stays where it already lives.

- **Identity/UI:** `id`, `display_name`, `description` (flavor only), `icon`,
  and `ability_tags` (e.g. `ability.spell.fire`, broadcast to passives).
- **Activation:** `cooldown`, `starting_cooldown`, `cost_pool` (e.g.
  `AttributeComponent.POOL_MANA`), `cost_amount` (0 = free), `required_tags`,
  `blocked_tags`.
- **Casting:** `cast_animation` (an AnimationTree state name), `release_time`
  (seconds into the cast, on the physics clock), `movement_speed`,
  `cancelable`, `uninterruptable`.
- **Release: reuses what exists, and every field is optional:**
  - `payload_scene: PackedScene`: any payload the game already has. That can
    be a projectile (the Fireball), a `DamageArea` hazard or explosion, or a
    VFX.
  - `payload_overrides: Array[PayloadPropertyOverride]`: the existing
    per-grant tuning resource (e.g. the Fireball's `damage` or `speed`).
  - `scale_with_attack: bool`: the existing opt-in attack-stat scaling from
    `PayloadPassiveAbility`, now also applied to projectiles.
  - `caster_effects: Array[GameplayEffect]`: applied to the caster at release,
    for self-buffs like haste or a shield.
- **Limit that comes with fixed slots:** an ability can't bring its own state
  script. What it does has to fit the data above, which covers projectiles,
  hazards, explosions, buffs and laser eyes. A leap or channeled ability
  would need the slot to hand off to another behavior later; that is not
  designed now.

## 8. Payload spawning, extracted instead of written again

Today two places instance a scene and send it into the world:
- `ProjectileSpawnerComponent.spawn_projectile()`: shooter, spawn point,
  facing yaw, ballistic setup;
- `PayloadPassiveAbility._activate()`: overrides, `DamageArea` wielder, damage
  scaling, position.

They merge into **one static `PayloadSpawner.spawn(scene, instigator, position,
direction, overrides, scale_with_attack) -> Node3D`** (in `Components/`). It:
1. instances the scene and applies the overrides;
2. hooks up the payload by type: a projectile gets its `shooter` (and the
   attack scaling when asked), a `DamageArea` gets `set_wielder()` and the
   scaling;
3. places it and turns it toward `direction`;
4. calls `VfxManager.spawn_world_entity()`, then the ballistic setup.

`ProjectileSpawnerComponent`, `PayloadPassiveAbility` and `AbilityCastState`
all call it. Enemy behavior is unchanged: the spawner passes no scaling. The
Akira boss's attack of 110 would otherwise start scaling its firebombs.

**Rename:** `EnemyProjectile` becomes `Projectile`, since the player now fires
it too; every caller is updated. Team handling needs no change. Projectiles
already skip their shooter's hurtbox, and their mask already includes the
enemy hurtbox layer, so the player's fireball hits enemies and never the
player.

## 9. Items: books and ability gear

- **`ItemResource.granted_abilities: Array[AbilityResource]`.** The item type
  decides how long the grant lasts, the same way it already does for
  `gameplay_effects`.
- **Teaching goes through one hook, `_grant_abilities(character)`**, called
  from `ItemResource.apply()`:
  - The base teaches for good (`grant_ability(a, null)`). That covers books,
    and consumables too, since `consume()` calls `apply()` (a future
    one-use scroll).
  - **`GearItemResource` overrides the hook to do nothing.** This matters
    because `EquipmentComponent.equip_gear()` calls `gear.apply()` for the
    instant effects before `attach()`; without the override, equipping gear
    would teach its ability for good. Gear grants instead from `attach()`,
    with itself as `source` (next to `_grant_passives()`), and
    `unequip()` calls `revoke_abilities_from(gear)`. A laser-eyes helm is a
    `.tres` file plus a payload scene.
  - There is no type check and no book subclass.
- **`can_apply()`:**
  - Plain items: false when the character already has every granted ability,
    or has no free slot.
  - Gear keeps its own rule, so gear is not refused for a full ability bar
    (see open question 3).
- **Summary lines:** "Teaches: Fireball" (plain items), "Grants: Laser Eyes"
  (gear).
- **`ItemResource.world_visual: PackedScene`:** how the item looks lying in a
  level (an `ItemDisplay`, see §11). Only items that have one can spawn in
  levels.
- `item_book_fireball.tres`: `title = "Fireball for Dummies"`,
  `granted_abilities = [ability_fireball]`, `world_visual = book_dummies.tscn`,
  `max_purchases = 1`.

## 10. Level item spawns (not keyed on level numbers)

- **`GlobalVars.level_items: Array[ItemResource]`:** the pool items can spawn
  from in levels. Today it holds only the Fireball book. Item difficulty
  tiers (for spawns, drops and the shop) are a future feature and are left
  out on purpose.
- **Shared availability:** the shop's `_has_stock_left()` moves to
  `ProgressionState.is_item_available(item)` and gains one run-state check:
  every granted ability is already learned, or no slot is free. The shop and
  level spawns both use it.
- **`ItemSpawner` node** (Node3D) in `level_template.tscn`, inherited by
  every level:
  - Exports: `player: Character` (typed, wired in the template), `count: int = 1`
    and `offset_from_player: Vector3`.
  - On level start it picks `count` random available items from the pool.
  - It places each one at the player's spawn + the offset, snapped to the
    navmesh once the navigation map has synced. This needs no edits in the
    14 levels.
- **Result:** the first level spawns the Fireball book because it is the only
  item. Once it is learned it is no longer available, so later levels spawn
  nothing. A book the player walks past shows up again on the next level.
- **Shop:** it deals from the same availability check. The book is **not**
  added to `GlobalVars.items`, since the spawn pool covers it.

## 11. Pickup and book art (styles are data, not code)

- **`ItemPickup`** (Area3D, `Items/Pickups/item_pickup.tscn`, registered as
  `GlobalVars.item_pickup_scene`): generic for every item.
  - It instances `item.world_visual` into a bobbing `Visual` node. The bob is
    visual only (render clock).
  - It detects the player's body layer. On contact it calls
    `equipment_component.apply_item(item)`.
  - Success: a sound, a small VFX and a floating "Learned: Fireball", then
    `queue_free`.
  - Failure: the book stays, with a throttled "No free ability slot" popup.
  - Later, a "pick it up?" dialog with a close-up of the item goes here.
- **`ItemDisplay`** (Node3D base class, `show_item(item)`): the contract every
  world visual fulfils. The pickup calls it, so visuals never reach into the
  pickup.
- **`BookModel extends ItemDisplay`** (`Items/Books/book_model.gd`, `@tool`
  so the editor previews it):
  - Builds the book from primitives only: a cover box, a pages box inset on
    three sides, and a spine strip.
  - Every look knob is an export: `size`, `cover_color`, `spine_color`,
    `page_color`, `cover_emission`, `title_label: Label3D`,
    `title_color`/`font`/`font_size`, and an optional `art_sprite: Sprite3D`
    with `art: Texture2D`.
  - `show_item(item)` writes the item's title, stripped of BBCode, into
    `title_label`.
- **Styles are scenes that inherit a base `book.tscn`:**
  - **`book_dummies.tscn`** (now): a yellow cover with a black top band and
    the title on the cover. No tagline, no mascot or real logo.
  - **`book_oreilly.tscn`** (later): a white cover, a colored band, an
    `art_sprite` holding an enemy picture, and a title like "Fireball: The
    Good Parts".
  - A specific book can inherit a style scene to set its own art. Changing
    the look means changing a scene or the inspector, never code.
- **Placement:** the book floats about 0.4 m up, tilted toward the camera and
  matched to its yaw (levels can rotate). It does not spin. An emissive floor
  ring marks it, with no dynamic light.
- **Legibility:** a quick `capture.py` check that the title roughly reads.
  It doesn't have to be perfect.

## 12. Input, HUD, persistence, animation, AI

- **Input:**
  - `project.godot` gets `ability_1`..`ability_4` → keys 1–4.
  - `PlayerInputComponent` gets an `ability_actions: Array[StringName]` export
    (index = slot). It warns if there are more slots than actions.
  - Casting follows the flow in §5.
- **HUD:**
  - An `ability_bar` sits bottom-center, with one widget per slot.
  - Each widget shows the icon, a radial cooldown sweep and a dimmed look when
    the ability can't be cast.
  - The key label is read from the InputMap, so rebinding shows up by itself.
  - It re-binds on a new `ProgressionState.player_bound(player)` signal.
  - The Fireball icon is a radial `GradientTexture2D` stored inside the
    `.tres` file.
- **Persistence:**
  - `ProgressionState.player_abilities` records only the **learned** abilities
    (source == null), per slot. It is updated from the ASC signals and cleared
    by `reset_run()`.
  - `bind_player()` calls `set_learned_abilities()` **before** restoring gear,
    so learned abilities keep their slots and gear abilities fill the free
    ones. On the run's first bind, the player's `starting_abilities` become
    the record.
  - Pending items are applied after that.
  - Cooldowns reset per level, because the player is new.
- **Animation:**
  - `Ranged_Magic_Shoot` from `Rig_Medium_CombatRanged.glb` becomes the
    `CastSpell` AnimationTree state, following the `add-combat-animation`
    skill. It uses the same BlendTree + TimeScale shape as the other attacks.
  - There are no method tracks: release is `release_time` in data (TODO item 10).
- **AI: no new AI state.**
  - An enemy with abilities wires slot states in its scene and sets
    `starting_abilities`.
  - An `AIConditionalAttack` (range + `can_activate()` gating, already
    written) or an `AIAttack` points its `body_state` export at the slot
    node. Ordering an empty slot is harmless, since the slot returns home at
    once.

## 13. Fireball content

- **`Abilities/AbilityResources/ability_fireball.tres`:**
  - `ability_tags = [&"ability.spell.fire"]`
  - `cooldown ≈ 2 s`
  - `cast_animation = &"CastSpell"`, `release_time` measured from the animation
  - `movement_speed ≈ 0.3`, `cancelable = true`
  - `payload_scene = projectile_fireball.tscn` (the existing fireball, with
    its fire damage and burn)
  - `payload_overrides` for the player's damage and speed
  - `scale_with_attack = true`
- **`Items/ItemResources/item_book_fireball.tres`:** see §9.

## 14. Phases (each ends with `python run_tests.py` green, lint included)

1. **Refactors:**
   - split `CharacterAttack` into `CharacterAction` + `CharacterAttack`, with
     `dash_cancel` → `cancelable`;
   - add gravity and the fall check in `CharacterAction` (the one intended
     behavior change: attacks fall off ledges);
   - `PassiveAbilityComponent` → `AbilitySystemComponent`;
   - `EnemyProjectile` → `Projectile`;
   - extract `PayloadSpawner` and move both callers onto it;
   - move the shop's stock check into `ProgressionState`.

   The existing suites prove nothing else changed. A new regression test
   covers an attack that runs off a ledge and falls.
2. **Active abilities:**
   - `AbilityResource` and `AbilityCastState`;
   - the ASC slots and `starting_abilities`;
   - `ability_requested` + `check_ability()`, the input actions and
     `order_ability()`;
   - the player's four slot nodes and `CastOrigin`;
   - the `CastSpell` animation and the fireball `.tres`.
3. **Items + persistence + HUD:**
   - `granted_abilities` with the `_grant_abilities()` hook (plain items and
     gear);
   - the run record and `player_bound`;
   - the ability bar.
4. **World items:** `ItemPickup`, `ItemDisplay`, `BookModel` + `book.tscn` +
   `book_dummies.tscn`, `GlobalVars.level_items`, the `ItemSpawner`, and a
   capture check.
5. **AI + docs:**
   - an arena enemy casting the Fireball through `AIConditionalAttack`;
   - the AGENTS.md §5 map (ASC, `CharacterAction`, ability slots);
   - TODO item 8 removed, plus follow-ups: migrate `RangedEnemy` to the
     ability, a replace-slot / pick-up dialog, mana regen and a bar, item
     difficulty tiers, and abilities with their own behavior (leap,
     channel).

## 15. Tests (mechanism only, per the `write-test` skill)

`test_active_abilities` (arena):
- **Granting:** fills the first free slot; a duplicate or full slots return
  -1; the slot count follows the wired slots.
- **Casting:** `press_action(&"ability_1")` spawns the payload at release,
  which damages an enemy through its Hurtbox and never the caster.
- **Blocked casts:** nothing happens during the cooldown, on an empty slot,
  or when the pool is too low for the cost.
- **Where casting is allowed:**
  - pressing during a dash, a jump or a fall does nothing;
  - pressing during a melee attack casts only inside its `cancelable` window;
  - another ability can't cut into a cast before release;
  - a dash cancels a cast when `cancelable` is set.
- **Events:** STARTED, ACTIVE and ENDED (sent once, with `completed`) reach a
  passive with a matching tag.
- **Gear:** equipping gear with `granted_abilities` grants the ability and
  unequipping revokes it. Equipping never teaches it for good (regression
  for the `apply()`-before-`attach()` order). A learned ability survives the
  unequip.
- **Persistence:** a fresh player bound through `bind_player()` gets its
  learned abilities back in the same slots, and gear abilities in free slots.
- **Books as items:** a book through `apply_item()` teaches its ability, and
  as a pending item it teaches the next player.
- **Pickups:** walking over a pickup teaches and frees it; with full slots it
  stays.
- **Availability:** an item whose abilities are all learned is no longer
  available (shop and spawns).
- **AI:** an enemy with a starting ability and an `AIConditionalAttack` on
  its slot casts at the player.

`test_passive_abilities`, `test_attack_component`, `test_combo_and_dash_cancel`,
`test_cancel_abilities` and `test_player_attack` must still pass through the
phase 1 refactors.

`test_item_spawner`: in every regular dungeon, a spawned item lands on the
navmesh, not over a pit, and reachable from the player's spawn. This follows
the `test_level_rotation_nav` pattern.

## 16. Open questions (recommendations in bold)

1. **Mana:** **support costs in data, but keep the Fireball cooldown-only**
   until mana regen and a bar exist.
2. **Melee attacks falling off ledges:** **accept it as a fix**; today they
   appear to hover. To be confirmed in phase 1 before changing anything.
3. **Equipping ability gear with all slots full:** **the gear still equips
   (its stats apply) and the ability is skipped with a popup**, until the
   replace-slot dialog exists. Refusing the equip is the alternative.
4. **Migrating `RangedEnemy` to the Fireball ability:** **a separate
   follow-up**, since it changes enemy timing.
