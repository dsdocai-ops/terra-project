extends GutTest
## Tests for the Lantern Staff (SPEC-weapons Magic row, W5-G8): its data, the
## charged beam's damage scale through WeaponController.build_hit, the light cone
## geometry, and the `lit` flag that the beam sets on enemies inside the cone
## (D-P6). Owned by weapons. Sync: the flag is host state; the cone helpers take
## `is_host` so the client refusal is testable in one process. The real player
## scene and the real enemy scene are used; no timers run.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const ENEMY_SCENE := "res://scenes/enemies/enemy_base.tscn"
const STAFF_DATA := "res://data/weapons/lantern_staff.tres"
const NODE_SCENE := "res://scenes/player/weapons/lantern_staff.tscn"

var _world: Node2D
var _player: Player
var _weapons: WeaponController


func before_each() -> void:
	_world = Node2D.new()
	add_child_autofree(_world)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_world.add_child(_player)
	_player.position = Vector2.ZERO
	_weapons = _player.get_node("WeaponController") as WeaponController


func _staff() -> WeaponData:
	return load(STAFF_DATA) as WeaponData


func _enemy_at(where: Vector2) -> Enemy:
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	_world.add_child(enemy)
	enemy.position = where
	enemy.add_to_group(Enemy.GROUP)
	return enemy


func _node() -> LanternStaffAttack:
	var node := (load(NODE_SCENE) as PackedScene).instantiate() as LanternStaffAttack
	node.player = _player
	node.weapons = _weapons
	node.aim_dir = Vector2.RIGHT
	add_child_autofree(node)
	return node


# --- the data --------------------------------------------------------------------------------

func test_the_lantern_staff_loads_as_an_unlocked_magic_weapon() -> void:
	var staff: WeaponData = _staff()
	assert_not_null(staff, "data/weapons/lantern_staff.tres loads")
	assert_eq(staff.id, &"lantern_staff")
	assert_eq(staff.type, WeaponData.Type.MAGIC, "the Magic row")
	assert_true(staff.unlocked_at_start, "unlocked at start (SPEC-weapons)")
	assert_eq(staff.light_combo.size(), 2, "a two-step light combo")
	assert_not_null(staff.heavy, "a charged heavy")
	assert_not_null(staff.skill, "a skill stub on the shared skill path")


# --- the charged beam's damage -----------------------------------------------------------------

func test_a_full_charge_hits_harder_than_no_charge() -> void:
	_weapons.equip(_weapons.active_slot, _staff())
	var spec: AttackSpec = _staff().heavy
	var empty: HitInfo = _weapons.build_hit(spec, Vector2.RIGHT, 0.0, true)
	var full: HitInfo = _weapons.build_hit(spec, Vector2.RIGHT, 1.0, true)
	assert_almost_eq(empty.base_damage, spec.base_damage, 0.001, "no charge, no bonus")
	assert_almost_eq(full.base_damage, spec.base_damage * (1.0 + WeaponController.HEAVY_CHARGE_BONUS), 0.001,
		"a full charge takes the controller's charge bonus")


# --- the cone geometry -------------------------------------------------------------------------

func test_in_cone_accepts_a_point_on_the_aim_inside_range() -> void:
	assert_true(LanternStaffAttack.in_cone(Vector2.ZERO, Vector2.RIGHT, Vector2(60, 0), _half()))


func test_in_cone_rejects_a_point_beyond_the_range() -> void:
	var beyond: Vector2 = Vector2.RIGHT * (LanternStaffAttack.ZERO_CHARGE_RANGE + 1.0)
	assert_false(LanternStaffAttack.in_cone(Vector2.ZERO, Vector2.RIGHT, beyond, _half()))


func test_in_cone_rejects_a_point_outside_the_half_angle() -> void:
	var off_axis: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(_half() + 5.0)) * 60.0
	assert_false(LanternStaffAttack.in_cone(Vector2.ZERO, Vector2.RIGHT, off_axis, _half()))


func test_in_cone_accepts_a_point_just_inside_the_half_angle() -> void:
	var inside: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(_half() - 5.0)) * 60.0
	assert_true(LanternStaffAttack.in_cone(Vector2.ZERO, Vector2.RIGHT, inside, _half()))


func test_in_cone_rejects_a_point_behind_the_aim() -> void:
	assert_false(LanternStaffAttack.in_cone(Vector2.ZERO, Vector2.RIGHT, Vector2(-60, 0), _half()))


func test_in_cone_accepts_the_apex() -> void:
	assert_true(LanternStaffAttack.in_cone(Vector2.ZERO, Vector2.RIGHT, Vector2.ZERO, _half()), "the staff's own tile is lit")


func test_a_zero_aim_lights_nothing_but_the_apex() -> void:
	assert_false(LanternStaffAttack.in_cone(Vector2.ZERO, Vector2.ZERO, Vector2(10, 0), _half()),
		"no direction, no cone")


# --- the lit flag, pure helper -----------------------------------------------------------------

func test_lit_targets_keeps_the_enemies_inside_the_cone_only() -> void:
	var near: Enemy = _enemy_at(Vector2(60, 0))
	var side: Enemy = _enemy_at(Vector2(0, 60))
	var far: Enemy = _enemy_at(Vector2(LanternStaffAttack.ZERO_CHARGE_RANGE + 40.0, 0))
	var candidates: Array[Node2D] = [near, side, far]
	var lit: Array[Node2D] = LanternStaffAttack.lit_targets(Vector2.ZERO, Vector2.RIGHT, candidates, true, _half())
	assert_eq(lit, [near] as Array[Node2D], "only the enemy inside the cone is lit")


func test_lit_targets_on_a_client_keeps_nothing() -> void:
	var near: Enemy = _enemy_at(Vector2(60, 0))
	var candidates: Array[Node2D] = [near]
	var lit: Array[Node2D] = LanternStaffAttack.lit_targets(Vector2.ZERO, Vector2.RIGHT, candidates, false, _half())
	assert_eq(lit.size(), 0, "the host alone sets lit; a client lights nothing")


func test_lit_targets_skips_nodes_that_are_not_enemies() -> void:
	var prop := Node2D.new()
	add_child_autofree(prop)
	prop.position = Vector2(60, 0)
	var candidates: Array[Node2D] = [prop]
	var lit: Array[Node2D] = LanternStaffAttack.lit_targets(Vector2.ZERO, Vector2.RIGHT, candidates, true, _half())
	assert_eq(lit.size(), 0, "a non-enemy in the cone is not lit")


# --- the attack node's heavy -------------------------------------------------------------------

func test_a_heavy_lights_the_enemies_in_the_cone() -> void:
	var inside: Enemy = _enemy_at(Vector2(80, 10))
	var outside: Enemy = _enemy_at(Vector2(-80, 0))
	var node: LanternStaffAttack = _node()
	node.heavy(1.0)
	assert_true(inside.lit, "inside the cone, host side")
	assert_false(outside.lit, "behind the staff, not lit")


func test_a_heavy_with_no_player_lights_nothing_and_does_not_fail() -> void:
	var inside: Enemy = _enemy_at(Vector2(80, 0))
	var node: LanternStaffAttack = _node()
	node.player = null
	node.heavy(1.0)
	assert_false(inside.lit, "no player, no cone")


func test_a_heavy_with_a_player_outside_the_tree_lights_nothing() -> void:
	var inside: Enemy = _enemy_at(Vector2(80, 0))
	var loose: Player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	autofree(loose)
	var node: LanternStaffAttack = _node()
	node.player = loose
	node.heavy(1.0)
	assert_false(inside.lit, "no tree, no group to read")


func test_a_non_2d_member_of_the_enemy_group_does_not_stop_the_beam() -> void:
	var odd := Node.new()
	_world.add_child(odd)
	odd.add_to_group(Enemy.GROUP)
	var inside: Enemy = _enemy_at(Vector2(80, 0))
	var node: LanternStaffAttack = _node()
	node.heavy(1.0)
	assert_true(inside.lit, "the 2D enemy beside the plain node is still lit")


func test_an_enemy_twenty_degrees_off_aim_is_neither_lit_nor_hit() -> void:
	# The lit cone and the heavy wedge share one angle (G8b): the wedge is arc_degrees
	# (30) wide, so its half angle is 15, and an enemy at 20 degrees is outside both.
	var inside: Enemy = _enemy_at(_at_angle(5.0, 80.0))
	var outside: Enemy = _enemy_at(_at_angle(20.0, 80.0))
	_node().heavy(1.0)
	assert_true(inside.lit, "inside the wedge, lit")
	assert_false(outside.lit, "20 degrees off aim is outside the wedge, so it is not lit")
	var wedge := _weapons._melee_shape(_staff().heavy, 1.0, true) as ConvexPolygonShape2D
	assert_true(Geometry2D.is_point_in_polygon(inside.position, wedge.points), "the wedge hits the inside enemy")
	assert_false(Geometry2D.is_point_in_polygon(outside.position, wedge.points), "the wedge misses the outside enemy")


func test_the_cone_half_angle_is_half_the_heavy_arc() -> void:
	assert_almost_eq(LanternStaffAttack.cone_half_angle_degrees(), _staff().heavy.arc_degrees * 0.5, 0.001,
		"read from lantern_staff.tres, arc_degrees / 2")


func _at_angle(degrees: float, distance: float) -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(degrees)) * distance


func _half() -> float:
	return LanternStaffAttack.cone_half_angle_degrees()


# --- the light bonus and the light's timer (host state) ----------------------------------------

func test_a_lit_enemy_takes_the_light_bonus() -> void:
	var inside: Enemy = _enemy_at(Vector2(80, 10))
	_node().heavy(1.0)
	assert_almost_eq(inside.hurtbox.damage_taken_factor(), LanternStaffAttack.LIT_DAMAGE_FACTOR, 0.001,
		"the Hurtbox factor the staggered state also uses")


func test_the_light_stays_for_lit_seconds_then_goes_out_with_its_bonus() -> void:
	var inside: Enemy = _enemy_at(Vector2(80, 10))
	var node: LanternStaffAttack = _node()
	node.heavy(1.0)
	node._physics_process(LanternStaffAttack.LIT_SECONDS - 0.5)
	assert_true(inside.lit, "still lit before the timer runs out")
	node._physics_process(0.6)
	assert_false(inside.lit, "lit runs out after LIT_SECONDS")
	assert_almost_eq(inside.hurtbox.damage_taken_factor(), 1.0, 0.001, "the bonus is cleared with the light")


func test_a_freed_enemy_is_dropped_from_the_timers_without_error() -> void:
	var inside: Enemy = _enemy_at(Vector2(80, 10))
	var node: LanternStaffAttack = _node()
	node.heavy(1.0)
	inside.free()
	node._physics_process(0.1)
	assert_eq(node._lit_left.size(), 0, "the freed enemy's entry is erased")


# --- the cone light in the scene -------------------------------------------------------------

func test_the_cone_light_is_drawn_from_the_scene_and_matches_the_geometry() -> void:
	var node: LanternStaffAttack = _node()
	var light := node.get_node("LightCone") as PointLight2D
	assert_not_null(light, "the scene carries the PointLight2D cone")
	assert_false(light.enabled, "the cone is off until a heavy")
	var image: Image = light.texture.get_image()
	var side: int = int(ceilf(WeaponController.melee_reach(_staff().heavy, 1.0, true))) * 2
	assert_eq(image.get_width(), side, "the texture spans the full-charge reach on each side")
	var centre := Vector2i(side / 2, side / 2)
	assert_gt(image.get_pixelv(centre + Vector2i(60, 0)).a, 0.0, "inside the cone along the aim")
	assert_eq(image.get_pixelv(centre + Vector2i(-60, 0)).a, 0.0, "behind the apex is dark")


func test_the_cone_light_turns_on_for_the_beam_and_off_after_it() -> void:
	var node: LanternStaffAttack = _node()
	var light := node.get_node("LightCone") as PointLight2D
	node.heavy(1.0)
	assert_true(light.enabled, "drawn while the beam runs")
	assert_almost_eq(light.rotation, Vector2.RIGHT.angle(), 0.001, "turned to the aim")
	node._physics_process(LanternStaffAttack.BEAM_SECONDS + 0.1)
	assert_false(light.enabled, "off after the beam")


# --- the lit cone reaches as far as the heavy (G8c) -------------------------------------------

func test_a_full_charge_lights_an_enemy_at_180_px_on_the_aim() -> void:
	var far: Enemy = _enemy_at(Vector2(180, 0))
	_node().heavy(1.0)
	assert_true(far.lit, "the full-charge heavy reaches about 202 px, so 180 px is inside the lit cone")


func test_at_zero_charge_the_reach_gate_decides_a_far_enemy() -> void:
	var far: Enemy = _enemy_at(Vector2(180, 0))
	_node().heavy(0.0)
	assert_false(far.lit, "no charge, the heavy reaches 150 px, so 180 px is outside")


func test_the_lit_cone_reaches_the_heavy_reach_at_full_charge() -> void:
	var reach: float = WeaponController.melee_reach(_staff().heavy, 1.0, true)
	var just_inside: Enemy = _enemy_at(Vector2(reach - 5.0, 0))
	var just_outside: Enemy = _enemy_at(Vector2(reach + 5.0, 0))
	_node().heavy(1.0)
	assert_true(just_inside.lit, "5 px inside the full-charge reach is lit")
	assert_false(just_outside.lit, "5 px past the full-charge reach is not lit")


func test_the_zero_charge_range_is_the_heavy_reach_at_no_charge() -> void:
	assert_almost_eq(LanternStaffAttack.ZERO_CHARGE_RANGE, WeaponController.melee_reach(_staff().heavy, 0.0, true), 0.001,
		"the constant the in_cone default uses is the heavy's reach at zero charge")


func test_the_drawn_cone_radius_matches_the_heavy_reach() -> void:
	var node: LanternStaffAttack = _node()
	var light := node.get_node("LightCone") as PointLight2D
	node.heavy(1.0)
	var radius: float = float(light.texture.get_width()) * 0.5 * light.texture_scale
	assert_almost_eq(radius, WeaponController.melee_reach(_staff().heavy, 1.0, true), 0.01,
		"the drawn cone reaches as far as the full-charge heavy")


func test_the_drawn_cone_radius_at_zero_charge_is_the_heavy_reach_at_no_charge() -> void:
	var node: LanternStaffAttack = _node()
	var light := node.get_node("LightCone") as PointLight2D
	node.heavy(0.0)
	var radius: float = float(light.texture.get_width()) * 0.5 * light.texture_scale
	assert_almost_eq(radius, WeaponController.melee_reach(_staff().heavy, 0.0, true), 0.01,
		"the drawn cone reaches as far as the uncharged heavy")


func test_the_cone_texture_edge_is_at_the_half_angle() -> void:
	var node: LanternStaffAttack = _node()
	var light := node.get_node("LightCone") as PointLight2D
	var image: Image = light.texture.get_image()
	var centre: float = float(image.get_width()) * 0.5
	var half: float = LanternStaffAttack.cone_half_angle_degrees()
	var inside: Vector2 = Vector2(centre, centre) + Vector2.RIGHT.rotated(deg_to_rad(half - 2.0)) * 120.0
	var outside: Vector2 = Vector2(centre, centre) + Vector2.RIGHT.rotated(deg_to_rad(half + 2.0)) * 120.0
	assert_gt(image.get_pixelv(Vector2i(floori(inside.x), floori(inside.y))).a, 0.0, "2 degrees inside the edge is lit")
	assert_eq(image.get_pixelv(Vector2i(floori(outside.x), floori(outside.y))).a, 0.0, "2 degrees outside the edge is dark")


func test_a_bare_node_with_no_light_child_still_lights_enemies() -> void:
	var inside: Enemy = _enemy_at(Vector2(80, 0))
	var bare := LanternStaffAttack.new()
	bare.player = _player
	bare.aim_dir = Vector2.RIGHT
	add_child_autofree(bare)
	bare.heavy(1.0)
	assert_true(inside.lit, "no cone light to draw, the lighting still runs")


func test_a_tick_on_a_bare_node_with_no_player_or_cone_runs_without_error() -> void:
	var bare := LanternStaffAttack.new()
	add_child_autofree(bare)
	bare._physics_process(0.1)
	assert_eq(bare._lit_left.size(), 0, "nothing lit, nothing to time")


func test_a_second_beam_restarts_the_light_timer() -> void:
	var inside: Enemy = _enemy_at(Vector2(80, 10))
	var node: LanternStaffAttack = _node()
	node.heavy(1.0)
	node._physics_process(LanternStaffAttack.LIT_SECONDS - 0.5)
	node.heavy(1.0)
	node._physics_process(LanternStaffAttack.LIT_SECONDS - 0.5)
	assert_true(inside.lit, "the second beam restarted the full LIT_SECONDS, so it is still lit")
