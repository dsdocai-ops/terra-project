class_name CaveInCast
extends AbilityCast
## Cave-In (SPEC-abilities section 8, Wren's ultimate; SPEC-abilities "Cave-In":
## "ceiling collapses on all enemies in the room: heavy damage, stun"). On spawn,
## every enemy in the caster's room takes one heavy hit, with the rank's `extra` as
## its hit-stun time (D-P4: the existing hit-stun path). The room is the one whose
## players_inside holds the caster, read through each enemy's room link. Owned by
## abilities. Sync: host only; the hits land on the host and the room is host state.

## The enemy's hurtbox child, the node Hurtbox.receive is called on.
const HURTBOX_NODE: NodePath = ^"Hurtbox"


func _perform() -> void:
	if player == null:
		return
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or enemy.room == null or not enemy.room.players_inside.has(player):
			continue
		var hurtbox := enemy.get_node_or_null(HURTBOX_NODE) as Hurtbox
		if hurtbox == null:
			continue
		hurtbox.receive(_room_hit())


## One heavy hit for one enemy, with the rank's stun time.
func _room_hit() -> HitInfo:
	var hit := build_hit()
	hit.is_heavy = true
	hit.hit_stun_seconds = extra()
	return hit
