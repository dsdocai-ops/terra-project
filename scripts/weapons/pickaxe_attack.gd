class_name PickaxeAttack
extends WeaponAttack
## The Pickaxe's per-weapon attack node (SPEC-weapons): its heavy cracks the
## ground in a line (SINKHOLE_SPEC section 7, Blades). The crack runs from the
## player along the aim as far as the charged heavy actually reaches, so the
## signature shows the real hitbox. Owned by weapons. Sync: none — the hook
## runs inside the swing each peer executes and the crack is local
## presentation that changes no game state.


func heavy(charge: float) -> void:
	var spec: AttackSpec = weapons.take_heavy() if weapons != null else null
	if spec == null or player == null:
		return
	var length: float = WeaponController.melee_reach(spec, charge, true)
	var dir: Vector2 = aim_dir if aim_dir.length() > 0.001 else Vector2.RIGHT
	GroundCrackLine.spawn(_crack_parent(), player.global_position, dir, length)


## Ground decals belong on the world's FX layer; a scene-less player (tests)
## falls back to the player's parent so the spawned node is always in the tree
## and findable.
func _crack_parent() -> Node:
	var world: World = GameState.world
	if world != null and is_instance_valid(world) and world.fx != null:
		return world.fx
	var home: Node = player.get_parent() if player != null else null
	return home if home != null else self
