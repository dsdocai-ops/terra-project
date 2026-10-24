class_name AttackPattern
extends Resource
## One enemy attack (SPEC-combat-core "Enemy attack contract"): windup with a
## telegraph, an active window, then recovery. Owned by combat-core, authored
## by enemies-ai. Sync: none (data). No attack may hit without a telegraph, so
## `windup_seconds` is at least MIN_WINDUP (a CI test asserts it).

enum Kind { MELEE, RUSH, PROJECTILE }
enum TelegraphShape { CIRCLE, CONE, LINE }

const MIN_WINDUP: float = 0.2

@export var id: StringName = &""
@export var kind: Kind = Kind.MELEE
@export var windup_seconds: float = 0.5
@export var active_seconds: float = 0.15
@export var recovery_seconds: float = 0.6
@export var telegraph_shape: TelegraphShape = TelegraphShape.CONE
## Telegraph size in px: x = length (or radius), y = width (cone degrees).
@export var telegraph_size: Vector2 = Vector2(60.0, 90.0)
@export var damage: float = 12.0
@export var knockback: float = 120.0
@export var hit_stun_seconds: float = 0.2
@export var element: HitInfo.Element = HitInfo.Element.NONE
## RUSH: dash speed while active. PROJECTILE: projectile speed.
@export var speed: float = 240.0
## The attack starts when the target is within this many px.
@export var trigger_range: float = 60.0
