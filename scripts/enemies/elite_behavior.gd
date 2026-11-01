class_name EliteBehavior
extends Node
## Base class for elite affix behaviours (SPEC-enemies-ai "Elites"). Enemy.setup
## adds one child of this per affixed elite, picked by `EliteAffix.behavior_script`.
## Owned by enemies-ai. Sync: host only. Enemy calls these from its host-side
## physics, damage and death paths, so a client never runs them and nothing here
## replicates; the affix itself reaches clients in the spawn payload.


## Called once on the host when the elite enters the tree (from Enemy._ready).
func on_spawn(_enemy: Enemy) -> void:
	pass


## Called every host physics frame with the TimeManager-scaled delta.
func process(_delta: float, _enemy: Enemy) -> void:
	pass


## True when this elite absorbs `hit` before it reaches Health (SHIELDED only).
func absorbs(_enemy: Enemy, _hit: HitInfo) -> bool:
	return false


## Called when the elite lands `damage` on a target (VAMPIRIC).
func on_dealt(_enemy: Enemy, _damage: int) -> void:
	pass


## Called when the elite dies, before it is freed.
func on_death(_enemy: Enemy, _hit: HitInfo) -> void:
	pass
