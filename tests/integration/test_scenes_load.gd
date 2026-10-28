extends GutTest
## Instantiates every .tscn under scenes/ to catch broken references, missing
## scripts, and parse errors early. Owned by foundation.


func _collect_scenes(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	assert_not_null(dir, "open %s" % dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect_scenes(full, out)
		elif entry.ends_with(".tscn"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func test_every_scene_instantiates() -> void:
	var scenes: Array[String] = []
	_collect_scenes("res://scenes", scenes)
	assert_gt(scenes.size(), 0, "found scenes")
	for path: String in scenes:
		var packed := load(path) as PackedScene
		assert_not_null(packed, "%s loads" % path)
		if packed == null:
			continue
		var node := packed.instantiate()
		assert_not_null(node, "%s instantiates" % path)
		if node != null:
			node.free()


## The enemies-ai base scene (W2-A9 G7b1) at the exact path the spec
## (SPEC-project folder layout, SPEC-enemies-ai) and the spawner's doc name:
## loads, instantiates as the `Enemy` script, and carries the wired base —
## the G7a1 machine states, the components the spawner's swap-in expects and
## the StateSync. The G7a2 pathing and G7a3 separation wiring on the script
## are exercised against this same scene by their unit suites.
func test_enemy_base_scene_loads_wired() -> void:
	var packed := load("res://scenes/enemies/enemy_base.tscn") as PackedScene
	assert_not_null(packed, "enemy_base.tscn loads")
	var node := packed.instantiate() as Node
	assert_not_null(node, "enemy_base.tscn instantiates")
	var enemy := node as Enemy
	assert_not_null(enemy, "enemy_base.tscn instantiates as the Enemy script")
	if enemy == null:
		if node != null:
			node.free()
		return
	assert_not_null(enemy.get_node_or_null("StatBlock"), "StatBlock")
	assert_not_null(enemy.get_node_or_null("Health"), "Health")
	assert_not_null(enemy.get_node_or_null("Hurtbox"), "Hurtbox")
	assert_not_null(enemy.get_node_or_null("Hitbox"), "Hitbox")
	assert_not_null(enemy.get_node_or_null("Telegraph"), "Telegraph")
	assert_not_null(enemy.get_node_or_null("StateSync"), "StateSync")
	var machine: Node = enemy.get_node("StateMachine")
	for state_name: String in ["Idle", "Chase", "Attack", "HitStun", "Stagger"]:
		assert_not_null(machine.get_node_or_null(NodePath(state_name)), "state %s" % state_name)
	enemy.free()


## The W2-A10 placeholder sprites: each enemy's SpriteFrames under assets/
## load, and every animation's frame texture loads with them (G8a adds the
## Hollow Miner; G8b appends the other two). The drawing itself — the enemy
## shows its frames instead of the placeholder polygon — is the
## test_v2_sprites suite.
func test_w2_a10_enemy_placeholder_sprites_load() -> void:
	var paths: Array[String] = [
		"res://assets/sprites/enemies/hollow_miner_frames.tres",
		"res://assets/sprites/enemies/rock_tick_frames.tres",
	]
	for path: String in paths:
		var frames: SpriteFrames = load(path) as SpriteFrames
		assert_not_null(frames, "%s loads as SpriteFrames" % path)
		if frames == null:
			continue
		var animations := frames.get_animation_names()
		assert_gt(animations.size(), 0, "%s has animations" % path)
		for animation: String in animations:
			var texture: Texture2D = frames.get_frame_texture(StringName(animation), 0)
			assert_not_null(texture, "%s / %s frame 0 loads" % [path, animation])
