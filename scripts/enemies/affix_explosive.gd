class_name AffixExplosive
extends EliteBehavior
## EXPLOSIVE (SPEC-enemies-ai): on death, a blast telegraphs for TELEGRAPH_SECONDS
## and then hits every player inside BLAST_RADIUS. The telegraph is the death fade
## the elite already plays, so the blast lands as the body clears. Owned by
## enemies-ai; host only. Damage goes through the player's Hurtbox.

const TELEGRAPH_SECONDS: float = 0.6
const BLAST_RADIUS: float = 72.0
const BLAST_DAMAGE: float = 12.0
const PLAYER_GROUP: StringName = &"player"


func on_death(enemy: Enemy, _hit: HitInfo) -> void:
	var tree := enemy.get_tree()
	if tree == null:
		return
	var timer := tree.create_timer(TELEGRAPH_SECONDS)
	timer.timeout.connect(_detonate.bind(enemy.global_position, enemy))


## Hits each player in BLAST_RADIUS of `at` through their Hurtbox. Host only (the
## Hurtbox refuses on clients). `source` is the dead elite, so the blast is
## attributed to it.
func _detonate(at: Vector2, source: Node) -> void:
	for node: Node in source.get_tree().get_nodes_in_group(PLAYER_GROUP):
		var player := node as Node2D
		if player == null or player.global_position.distance_to(at) > BLAST_RADIUS:
			continue
		var hurtbox := player.get_node_or_null("Hurtbox") as Hurtbox
		if hurtbox == null:
			continue
		var hit := HitInfo.new()
		hit.base_damage = BLAST_DAMAGE
		hit.source = source
		hurtbox.receive(hit)
