class_name WeaponAttack
extends Node
## Base for the per-weapon attack nodes (SPEC-weapons `WeaponAttack`): the
## WeaponController keeps one per weapon id and calls these hooks the moment a
## swing of that weapon goes live, so a weapon's signature ships as its
## `.tres` plus this script and a scene — never a new system. The generic
## hitbox, slash arc and projectile fire stay in `WeaponController`; a hook
## only adds what is specific to the weapon. Owned by weapons. Sync: the hooks
## run inside the swing each peer already executes (the owner's prediction,
## the host's authority), so anything a hook spawns must be local presentation
## that changes no game state.

var weapons: WeaponController = null
var player: Player = null
## The swing's aim direction, set by the controller just before the hook runs.
var aim_dir: Vector2 = Vector2.DOWN


## The light combo step `step` (0-based) went live.
func light(_step: int) -> void:
	pass


## The heavy went live at charge `charge` (0..1).
func heavy(_charge: float) -> void:
	pass


## The weapon skill went live.
func skill() -> void:
	pass
