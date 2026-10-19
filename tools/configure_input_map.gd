extends SceneTree
## Writes the Input Map from SPEC-foundation into project.godot.
## Owned by foundation. Sync: none.
##
## Run from the repo root, then commit project.godot:
##   godot --headless --path . -s tools/configure_input_map.gd
##
## This file is the canonical binding list. Change it here, rerun, and the
## test in tests/unit/test_input_map.gd keeps project.godot honest.
## Controller layout note (decided 2026-10-18): the spec table put A on both
## interact and ability_2 and wanted L3+R3 for ultimate; the Input Map has no
## chords, so ability_2 is RB, ability_3 is R3, ultimate is L3, interact is A.

const DEADZONE := 0.5


func _init() -> void:
	_define(&"move_up", [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_define(&"move_down", [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_define(&"move_left", [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_define(&"move_right", [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_define(&"attack_light", [_mouse(MOUSE_BUTTON_LEFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_define(&"attack_heavy", [_mouse(MOUSE_BUTTON_RIGHT), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_define(&"dodge", [_key(KEY_SPACE), _joy(JOY_BUTTON_B)])
	_define(&"class_skill", [_key(KEY_SHIFT), _joy(JOY_BUTTON_LEFT_SHOULDER)])
	_define(&"swap_weapon", [_mouse(MOUSE_BUTTON_WHEEL_UP), _mouse(MOUSE_BUTTON_WHEEL_DOWN), _joy(JOY_BUTTON_Y)])
	_define(&"weapon_1", [_key(KEY_1)])
	_define(&"weapon_2", [_key(KEY_2)])
	_define(&"ability_1", [_key(KEY_Q), _joy(JOY_BUTTON_X)])
	_define(&"ability_2", [_key(KEY_R), _joy(JOY_BUTTON_RIGHT_SHOULDER)])
	_define(&"ability_3", [_key(KEY_V), _joy(JOY_BUTTON_RIGHT_STICK)])
	_define(&"ultimate", [_key(KEY_X), _joy(JOY_BUTTON_LEFT_STICK)])
	_define(&"relic_active_1", [_key(KEY_C), _joy(JOY_BUTTON_DPAD_LEFT)])
	_define(&"relic_active_2", [_key(KEY_B), _joy(JOY_BUTTON_DPAD_RIGHT)])
	_define(&"potion", [_key(KEY_E), _joy(JOY_BUTTON_DPAD_UP)])
	_define(&"interact", [_key(KEY_F), _joy(JOY_BUTTON_A)])
	_define(&"inventory", [_key(KEY_TAB), _joy(JOY_BUTTON_BACK)])
	_define(&"ping", [_mouse(MOUSE_BUTTON_MIDDLE), _joy(JOY_BUTTON_DPAD_DOWN)])
	_define(&"pause", [_key(KEY_ESCAPE), _joy(JOY_BUTTON_START)])
	_define(&"debug_console", [_key(KEY_QUOTELEFT)])

	var err := ProjectSettings.save()
	if err != OK:
		push_error("failed to save project.godot: %s" % error_string(err))
		quit(1)
		return
	print("input map written to project.godot")
	quit()


func _define(action: StringName, events: Array[InputEvent]) -> void:
	ProjectSettings.set_setting("input/%s" % action, {"deadzone": DEADZONE, "events": events})


## Bindings match input from any device, as the editor's Input Map panel
## stores them. A freshly constructed event carries a specific device id,
## which would silently fail to match real hardware.
const ANY_DEVICE := -1


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.device = ANY_DEVICE
	return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.device = ANY_DEVICE
	return e


func _joy(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.device = ANY_DEVICE
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	e.device = ANY_DEVICE
	return e
