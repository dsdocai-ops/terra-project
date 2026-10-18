# Spec: player-controller

| | |
|---|---|
| Module id | `player-controller` |
| Owner | Dev A |
| Weeks | 1 (movement, camera), 2 (dodge, perfect dodge, hit reactions with combat-core), 3 (downed and revive) |
| Design doc | sections 5, 6, 12 (downed state, camera framing), 17 (8-direction sprites) |
| Depends on | `foundation`, `networking` |
| Depended on by | `combat-core`, `weapons`, `abilities`, `classes-characters`, `ui-hud` |

## Objective

The player character that feels good to move before anything else exists: 8-direction isometric movement, a dodge roll with i-frames and a perfect-dodge window, a state machine other modules plug states into, 8-direction sprite handling, and a camera that frames one player or four. Also the downed state and revive, because co-op is week 1.

## Scope

### Movement

- `CharacterBody2D`. Input vector from the four `move_*` actions, rotated through `Iso.input_to_world()` so W moves up-screen along the isometric axis. Diagonal and cardinal on-screen speeds equal.
- Speed from `StatBlock.get_value(Stat.MOVE_SPEED)`; base 120 px/s, tuned in week 2.
- Acceleration and friction short (reach full speed in ~4 frames) so it feels snappy.
- Facing: 8 directions from the aim vector (mouse position relative to player) while attacking, from the move vector otherwise. Stored as `facing_index: int` 0 to 7 and `facing: Vector2`.

### Dodge roll

- `dodge` action. Fixed distance (~96 px, Rebound Spring doubles via a stat-like multiplier exposed as `dodge_distance_mult`), duration ~0.25 s, cooldown from `Stat.DODGE_COOLDOWN` base 0.8 s.
- I-frames for the full roll. `Hurtbox.invulnerable = true` while rolling.
- **Perfect dodge**: if an enemy hitbox would have hit the player during the first 0.12 s of the roll, emit `Events.player_dodged(player, true)` and open a `perfect_dodge_window` for 0.5 s (consumed by `weapons` for the weapon skill, by `progression-trees` Perfect Dodge node for time slow). Detection is done by `combat-core`'s Hurtbox reporting a blocked hit during i-frames; this module owns the window timer.
- Dodge charges: default 1, `Phantom Dancer` synergy sets 2. Exposed as `dodge_charges: int`.
- Kestrel passive (30% instant reset) hooks `dodge_finished` and calls `reset_dodge_cooldown()`.

### State machine

`scripts/components/state_machine.gd` + `state.gd` (shared with enemies and bosses). Player states: `Idle`, `Move`, `Dodge`, `AttackLight`, `AttackHeavyCharge`, `AttackHeavyRelease`, `ClassSkill`, `AbilityCast`, `HitStun`, `Downed`, `Dead`, `Interact`. Attack states are driven by `combat-core` and `weapons`; this module defines the machine, `Idle`, `Move`, `Dodge`, `HitStun`, `Downed`, `Dead`, `Interact`.

Transitions are requested through `state_machine.change_to(name)` and states can refuse (e.g. `Downed` refuses everything but `revive`).

### Sprites

- `AnimatedSprite2D` with animations named `<state>_<dir>` where dir is one of `s, sw, w, nw, n, ne, e, se`. Helper `play_directional(anim: String)` picks the suffix from `facing_index`.
- Placeholder: colored diamond with a facing arrow until `art-audio` delivers sheets.

### Camera

- `Camera2D` with `position_smoothing_enabled`, speed tuned ~8.
- Solo: follows local player.
- Co-op: frames all living players. Target is the centroid; zoom out until all players fit with 96 px margin, clamp zoom between 1.0 and 0.6. Players cannot leave the frame; movement is clamped to the camera bounds so no one runs offscreen (design doc: shared camera, zooms to fit).
- Shake: `shake(strength: float, duration: float)` trauma-based, respects `settings.screen_shake` 0 to 1.
- Hit-stop interaction: camera does not freeze during hit-stop.

### Downed and revive

- At HP 0 the player enters `Downed`: cannot move, cannot be targeted for damage by default, shows a bleed-out timer of 30 s. Teammates hold `interact` within 48 px for 3 s to revive to 40% HP. Revive speed multipliers come from `StatBlock` via a `revive_speed_mult` stat-like field (Field Medic, Sanctuary).
- Solo: downed is skipped, `Dead` immediately. Second Wind, Undying, Phoenix intercept via `Health.about_to_die` (see combat-core) before `Downed`/`Dead`.
- If every player is downed or dead, `run-economy` ends the run (it listens to `Events.player_downed`).
- Timer expiry in co-op: `Dead` for the rest of the floor; revives at next floor start at 50% HP.

### Interact

`interact` press: nearest `Interactable` (area with `interact(player)` method and `prompt_text`) within 40 px. Hold handled for revive only. Prompt display is `ui-hud`.

## Interfaces provided

`Player` (`scenes/player/player.gd`):

```gdscript
signal downed()
signal revived(by: Player)
signal dodge_started(perfect_window_open: bool)
signal dodge_finished()
signal facing_changed(index: int)

var peer_id: int
var character: CharacterData
var class_data: ClassData
var stat_block: StatBlock
var health: Health
var hurtbox: Hurtbox
var state_machine: StateMachine
var facing: Vector2
var facing_index: int
var aim_position: Vector2            # world position of cursor
var is_downed: bool
var is_local: bool
var dodge_charges: int = 1
var dodge_distance_mult: float = 1.0
var revive_speed_mult: float = 1.0

func is_perfect_dodge_window() -> bool
func consume_perfect_dodge_window() -> void
func reset_dodge_cooldown() -> void
func play_directional(anim: String) -> void
func request_revive(target: Player) -> void      # client -> host
```

`GameCamera` (`scenes/main/camera.gd`): `shake(strength, duration)`, `set_targets(players: Array[Player])`.

`Interactable` (`scripts/components/interactable.gd`): `prompt_text: String`, `func interact(player: Player) -> void`, `hold_seconds: float = 0.0`.

## Interfaces consumed

- `networking`: `InputSync` / `StateSync` layout, `NetworkManager.players`, `request_*` RPC naming.
- `foundation`: input actions, `Iso`, world node layout.
- `stats-status`: `StatBlock` for `MOVE_SPEED`, `DODGE_COOLDOWN` (stub acceptable in week 1).
- `combat-core`: `Health`, `Hurtbox` (week 2).

## Data model

No Resources. Player scene composition:

```
Player (CharacterBody2D)
  StatBlock, Health, Hurtbox, StatusEffects   (components)
  StateMachine / states...
  Sprite (AnimatedSprite2D)
  WeaponPivot (Node2D)                        weapons module attaches here
  InputSync, StateSync (MultiplayerSynchronizer)
  InteractArea (Area2D)
```

## Multiplayer ownership

Input and presentation: owning peer. Position of record, HP, downed state: host. Client predicts its own movement; host corrects. Dodge start is client-predicted for feel; i-frames are granted by the host when it processes the dodge, which means a laggy client can be hit in the first frames; accepted for 12 weeks and noted in the settings text.

## Testing

- Unit: `test_player_facing.gd` (aim vector to facing index for all 8 sectors), `test_dodge_timing.gd` (window opens and closes, charges decrement and refill, Kestrel reset path).
- Integration: scene load; state machine refuses invalid transitions from `Downed`.
- Manual: feel checklist each week (acceleration, roll distance, camera smoothing), co-op camera with 4 instances spread across a room, downed and revive two-instance smoke.

## Success criteria

- [ ] Week 1: WASD moves along isometric axes at equal on-screen speed in all 8 directions; camera follows; two instances see each other move.
- [ ] Week 2: dodge roll with i-frames; perfect dodge window fires `Events.player_dodged(player, true)` only when a hit was blocked in the first 0.12 s.
- [ ] Week 3: downed, hold-F revive, bleed-out timer, all synced; solo goes straight to Dead.
- [ ] Co-op camera keeps 4 players in frame at zoom no lower than 0.6 and clamps movement at the edges.
- [ ] 8-direction animation switching has no visible pops when circling the mouse.

## Open questions

- Exact movement speed, roll distance, and acceleration numbers are tuned in week 2 and written back here.
