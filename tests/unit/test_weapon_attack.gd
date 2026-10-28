extends GutTest

## Tests for `scripts/weapons/weapon_attack.gd` (W2-A7, G16a): the WeaponAttack
## base every per-weapon attack node extends, mirrored by file name per BRIEF
## DoD 5. The controller's routing of a live swing into these hooks and the
## Pickaxe/Crossbow overrides stay in `test_pickaxe_attack.gd` and
## `test_crossbow_attack.gd`; this file is the base's own contract — the
## defaults, the no-op hooks and the override seam.


class HookSpy:
	extends WeaponAttack
	## Records which hooks a caller fires (named methods; a lambda connect
	## never fires in GUT).
	var lights: Array[int] = []
	var heavies: Array[float] = []
	var skills: int = 0

	func light(step: int) -> void:
		lights.append(step)

	func heavy(charge: float) -> void:
		heavies.append(charge)

	func skill() -> void:
		skills += 1


func _bare() -> WeaponAttack:
	var node: WeaponAttack = WeaponAttack.new()
	autofree(node)
	return node


# --- the defaults ----------------------------------------------------------------------------

func test_a_bare_attack_node_carries_the_neutral_defaults() -> void:
	var node: WeaponAttack = _bare()
	assert_null(node.weapons, "wired by the controller when it makes the node")
	assert_null(node.player, "ditto")
	assert_eq(node.aim_dir, Vector2.DOWN, "the swing's aim, set just before the hook runs")
	assert_eq(node.shot_scale, 1.0, "1.0 = the scene's own projectile size")


# --- the default hooks are no-ops ------------------------------------------------------------

func test_the_default_hooks_run_and_change_nothing() -> void:
	var node: WeaponAttack = _bare()
	node.light(1)
	node.heavy(0.65)
	node.skill()
	assert_eq(node.shot_scale, 1.0, "the generic hooks leave the shot at its scene size")
	assert_eq(node.aim_dir, Vector2.DOWN)


func test_the_base_node_fits_the_controller_typed_registry() -> void:
	# WeaponController's `_attack_nodes` holds `WeaponAttack` and every hook
	# call sites the base type, so the base itself must be usable as the node.
	var node: WeaponAttack = _bare()
	assert_is(node, WeaponAttack)
	assert_is(node, Node)


# --- the override seam -----------------------------------------------------------------------

func test_a_weapon_overrides_exactly_the_hooks_it_needs() -> void:
	var spy: HookSpy = HookSpy.new()
	autofree(spy)
	assert_is(spy, WeaponAttack, "the controller's typed slots take any subclass")
	spy.light(2)
	spy.heavy(0.5)
	spy.skill()
	assert_eq(spy.lights, [2] as Array[int], "the light step reaches the override")
	assert_eq(spy.heavies, [0.5] as Array[float], "the charge reaches the override")
	assert_eq(spy.skills, 1, "the skill fires once")
	spy.shot_scale = 1.5
	assert_eq(spy.shot_scale, 1.5, "a charged weapon's hook sets the scale per swing")
