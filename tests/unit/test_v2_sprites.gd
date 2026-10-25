extends GutTest
## The v2 sprite sheets are wired in (SPEC-art-audio "Art direction v2"): the
## player draws Wren's 64x96 frames, and an enemy draws its EnemyData frames,
## falling back to the placeholder polygon when its data has none.
## Owned by art-audio (the sprite seam into player-controller and enemies-ai).

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const BIOME_1_WITH_ART: Array[StringName] = [&"hollow_miner", &"rock_tick", &"lantern_wisp"]


func _enemy(kind: StringName) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	assert_true(enemy.setup(kind), "%s sets up" % kind)
	add_child_autofree(enemy)
	return enemy


func test_biome_1_enemies_draw_their_sprite_not_the_polygon() -> void:
	for kind: StringName in BIOME_1_WITH_ART:
		var enemy := _enemy(kind)
		var sprite := enemy.get_node("Sprite") as AnimatedSprite2D
		assert_true(sprite.visible, "%s sprite shows" % kind)
		assert_false((enemy.get_node("Body") as Polygon2D).visible, "%s polygon hides" % kind)
		assert_eq(sprite.sprite_frames, enemy.data.sprite_frames)
		assert_true(sprite.is_playing(), "%s animates" % kind)


func test_sprite_feet_sit_on_the_enemy_origin() -> void:
	var enemy := _enemy(&"hollow_miner")
	var sprite := enemy.get_node("Sprite") as AnimatedSprite2D
	var height: float = float(enemy.data.sprite_frames.get_frame_texture(&"idle_s", 0).get_height())
	assert_eq(height, 96.0, "hollow miner uses the 64x96 humanoid frame")
	assert_eq(sprite.position, Vector2(0.0, -44.0), "feet 4 px above the frame bottom land on the origin")


func test_enemy_without_frames_keeps_the_placeholder_polygon() -> void:
	var enemy := _enemy(&"grub")
	assert_null(enemy.data.sprite_frames)
	assert_false((enemy.get_node("Sprite") as AnimatedSprite2D).visible)
	assert_true((enemy.get_node("Body") as Polygon2D).visible)


func test_moving_enemy_plays_a_walk_animation_for_its_facing() -> void:
	var enemy := _enemy(&"hollow_miner")
	var sprite := enemy.get_node("Sprite") as AnimatedSprite2D
	enemy.global_position += Vector2(10.0, 0.0)
	enemy._process(0.016)
	assert_eq(sprite.animation, &"walk_e", "moving right faces east")


func test_player_draws_wren_v2_frames() -> void:
	var player := PLAYER_SCENE.instantiate()
	var sprite := player.get_node("Sprite") as AnimatedSprite2D
	assert_eq(sprite.sprite_frames.resource_path, "res://assets/sprites/players/wren_frames.tres")
	for suffix: StringName in Facing.SUFFIXES:
		assert_true(sprite.sprite_frames.has_animation(StringName("idle_%s" % suffix)), "idle_%s" % suffix)
		assert_true(sprite.sprite_frames.has_animation(StringName("walk_%s" % suffix)), "walk_%s" % suffix)
	assert_eq(sprite.position, Vector2(0.0, -44.0))
	player.free()
