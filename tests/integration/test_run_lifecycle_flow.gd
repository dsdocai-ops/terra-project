extends GutTest
## Integration: the run lifecycle drives the real HUD scene, not just the
## signal counts the unit test watches (LESSONS: a green GUT suite is not
## runtime-clean — cross-module signal seams need the real scene, as the
## W2-B5 signal-arity bug showed). Owned by run-economy; the HUD belongs to
## ui-hud and is loaded, never modified, here.

const HUD_SCENE := "res://scenes/ui/hud.tscn"

var _hud: Hud


func before_each() -> void:
	GameState.run = null
	GameState.forced_seed = 0
	_hud = (load(HUD_SCENE) as PackedScene).instantiate() as Hud
	add_child_autofree(_hud)
	NetworkManager.start_solo()


func after_each() -> void:
	GameState.run = null
	GameState.forced_seed = 0
	NetworkManager.disconnect_all()


func test_floor_label_follows_the_run_lifecycle() -> void:
	var label := _hud.floor_sign
	assert_eq(label.floor_text, "FLOOR -", "the HUD placeholders until the first floor arrives")
	GameState.start_run(77, 1, [])
	GameState.next_floor()
	assert_eq(label.floor_text, "FLOOR 2",
		"floor_changed reaches the HUD through its Resource-typed biome parameter")
	GameState.end_run(RunEndReason.Reason.ABORT)
	assert_eq(label.floor_text, "FLOOR 2", "ending the run leaves the last floor on screen")


func test_run_result_reaches_a_run_ended_listener() -> void:
	# Named callback, never a lambda (LESSONS: `.connect(lambda)` never fires).
	var recorder := _ResultRecorder.new()
	GameState.run_ended.connect(recorder.on_run_ended)
	GameState.start_run(88, 4, [])
	GameState.end_run(RunEndReason.Reason.EXTRACT)
	GameState.run_ended.disconnect(recorder.on_run_ended)
	assert_eq(recorder.results.size(), 1)
	assert_eq(recorder.results[0].reason, RunEndReason.Reason.EXTRACT)
	assert_eq(recorder.results[0].seed, 88)
	assert_eq(recorder.results[0].floors_cleared, 0)


class _ResultRecorder:
	extends RefCounted

	var results: Array[RunResult] = []

	func on_run_ended(result: RefCounted) -> void:
		var typed: RunResult = result as RunResult
		if typed != null:
			results.append(typed)
