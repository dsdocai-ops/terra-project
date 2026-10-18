extends GutTest
## Tests for the Input Map from the SPEC-foundation table. Owned by foundation.
## InputMap is loaded from project.godot at startup, so this reads the real
## bindings.

## Gameplay actions: keyboard/mouse plus a controller event each.
const GAMEPLAY_ACTIONS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right",
	&"attack_light", &"attack_heavy", &"dodge", &"class_skill", &"swap_weapon",
	&"ability_1", &"ability_2", &"ability_3", &"ultimate",
	&"relic_active_1", &"relic_active_2", &"potion", &"interact",
	&"inventory", &"ping", &"pause",
]
## Keyboard-only by design.
const KEYBOARD_ONLY_ACTIONS: Array[StringName] = [&"weapon_1", &"weapon_2", &"debug_console"]


func _has_event(action: StringName, predicate: Callable) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if predicate.call(event):
			return true
	return false


func _has_key(action: StringName, keycode: Key) -> bool:
	return _has_event(action, func(e: InputEvent) -> bool:
		var k := e as InputEventKey
		return k != null and k.physical_keycode == keycode)


func _has_mouse(action: StringName, button: MouseButton) -> bool:
	return _has_event(action, func(e: InputEvent) -> bool:
		var m := e as InputEventMouseButton
		return m != null and m.button_index == button)


func _has_joy_button(action: StringName, button: JoyButton) -> bool:
	return _has_event(action, func(e: InputEvent) -> bool:
		var j := e as InputEventJoypadButton
		return j != null and j.button_index == button)


func _has_joy_axis(action: StringName, axis: JoyAxis, sign: float) -> bool:
	return _has_event(action, func(e: InputEvent) -> bool:
		var j := e as InputEventJoypadMotion
		return j != null and j.axis == axis and signf(j.axis_value) == sign)


func _has_controller_event(action: StringName) -> bool:
	return _has_event(action, func(e: InputEvent) -> bool:
		return e is InputEventJoypadButton or e is InputEventJoypadMotion)


func _has_keyboard_or_mouse_event(action: StringName) -> bool:
	return _has_event(action, func(e: InputEvent) -> bool:
		return e is InputEventKey or e is InputEventMouseButton)


func test_every_action_exists() -> void:
	for action: StringName in GAMEPLAY_ACTIONS + KEYBOARD_ONLY_ACTIONS:
		assert_true(InputMap.has_action(action), String(action))


func test_gameplay_actions_have_keyboard_and_controller_bindings() -> void:
	for action: StringName in GAMEPLAY_ACTIONS:
		assert_true(_has_keyboard_or_mouse_event(action), "%s keyboard/mouse" % action)
		assert_true(_has_controller_event(action), "%s controller" % action)


func test_keyboard_only_actions_have_a_key() -> void:
	for action: StringName in KEYBOARD_ONLY_ACTIONS:
		assert_true(_has_keyboard_or_mouse_event(action), "%s key" % action)


func test_movement_is_wasd_and_left_stick() -> void:
	assert_true(_has_key(&"move_up", KEY_W))
	assert_true(_has_key(&"move_down", KEY_S))
	assert_true(_has_key(&"move_left", KEY_A))
	assert_true(_has_key(&"move_right", KEY_D))
	assert_true(_has_joy_axis(&"move_up", JOY_AXIS_LEFT_Y, -1.0))
	assert_true(_has_joy_axis(&"move_down", JOY_AXIS_LEFT_Y, 1.0))
	assert_true(_has_joy_axis(&"move_left", JOY_AXIS_LEFT_X, -1.0))
	assert_true(_has_joy_axis(&"move_right", JOY_AXIS_LEFT_X, 1.0))


func test_attacks_are_mouse_buttons_and_triggers() -> void:
	assert_true(_has_mouse(&"attack_light", MOUSE_BUTTON_LEFT))
	assert_true(_has_mouse(&"attack_heavy", MOUSE_BUTTON_RIGHT))
	assert_true(_has_joy_axis(&"attack_light", JOY_AXIS_TRIGGER_RIGHT, 1.0))
	assert_true(_has_joy_axis(&"attack_heavy", JOY_AXIS_TRIGGER_LEFT, 1.0))


func test_core_keys_match_the_table() -> void:
	assert_true(_has_key(&"dodge", KEY_SPACE))
	assert_true(_has_key(&"class_skill", KEY_SHIFT))
	assert_true(_has_key(&"weapon_1", KEY_1))
	assert_true(_has_key(&"weapon_2", KEY_2))
	assert_true(_has_key(&"ability_1", KEY_Q))
	assert_true(_has_key(&"ability_2", KEY_R))
	assert_true(_has_key(&"ability_3", KEY_V))
	assert_true(_has_key(&"ultimate", KEY_X))
	assert_true(_has_key(&"relic_active_1", KEY_C))
	assert_true(_has_key(&"relic_active_2", KEY_B))
	assert_true(_has_key(&"potion", KEY_E))
	assert_true(_has_key(&"interact", KEY_F))
	assert_true(_has_key(&"inventory", KEY_TAB))
	assert_true(_has_key(&"pause", KEY_ESCAPE))
	assert_true(_has_key(&"debug_console", KEY_QUOTELEFT))


func test_swap_weapon_is_wheel_both_ways_and_y() -> void:
	assert_true(_has_mouse(&"swap_weapon", MOUSE_BUTTON_WHEEL_UP))
	assert_true(_has_mouse(&"swap_weapon", MOUSE_BUTTON_WHEEL_DOWN))
	assert_true(_has_joy_button(&"swap_weapon", JOY_BUTTON_Y))


func test_ping_is_middle_click() -> void:
	assert_true(_has_mouse(&"ping", MOUSE_BUTTON_MIDDLE))


func test_synthetic_key_press_triggers_action_through_input_singleton() -> void:
	# Guards the saved event encoding (device ids, physical keycodes): a real
	# key event from device 0 must match the stored binding.
	var press := InputEventKey.new()
	press.physical_keycode = KEY_W
	press.pressed = true
	press.device = 0
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	assert_true(Input.is_action_pressed(&"move_up"), "W pressed drives move_up")
	var release := InputEventKey.new()
	release.physical_keycode = KEY_W
	release.pressed = false
	release.device = 0
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	assert_false(Input.is_action_pressed(&"move_up"), "release clears it")


func test_synthetic_joypad_axis_drives_move_vector() -> void:
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = 1.0
	motion.device = 0
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	var v := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	assert_almost_eq(v.x, 1.0, 0.01, "stick right drives move_right")
	# A fresh event for the release: Godot refuses to parse the same object twice.
	var centered := InputEventJoypadMotion.new()
	centered.axis = JOY_AXIS_LEFT_X
	centered.axis_value = 0.0
	centered.device = 0
	Input.parse_input_event(centered)
	Input.flush_buffered_events()


func test_controller_face_buttons_do_not_collide() -> void:
	# Every joypad button is bound to at most one action, so pressing A
	# cannot trigger both interact and an ability.
	var seen: Dictionary[int, StringName] = {}
	for action: StringName in GAMEPLAY_ACTIONS + KEYBOARD_ONLY_ACTIONS:
		for event: InputEvent in InputMap.action_get_events(action):
			var j := event as InputEventJoypadButton
			if j == null:
				continue
			assert_false(seen.has(j.button_index), "button %d bound to both %s and %s" % [j.button_index, seen.get(j.button_index, &""), action])
			seen[j.button_index] = action
