extends GutTest
## Tests for the AudioManager autoload (SPEC-art-audio): the two-player music
## crossfade state machine, the pooled positional and non-positional SFX, bus
## volume mapping on the four buses, the SfxBank covering the week-2 ids with
## placeholder clicks, and the missing-id fallback. Owned by art-audio.
##
## Autoload state is shared across the whole GUT run, so after_each resets
## every side effect this file can leave behind (LESSONS G6). Fades are driven
## with explicit _tick_fades calls (no awaits), so the idle _process cannot
## drift the assertions.
##
## A pooled player stands still for exactly as long as the stream under it has
## audio left, and `playing` flips false the moment the audio thread mixes past
## that end: the bank's real `ui_click` is 1448 bytes (~16 ms). Any test that
## needs a pooled player to still be busy therefore fills the pool with
## `_looping_click()` instead of a real click, so the property it asserts is the
## fixture's and not the machine's speed.

const WEEK2_SFX_IDS: Array[StringName] = [
	&"hit_light", &"hit_heavy", &"crit", &"dodge", &"perfect_dodge",
	&"enemy_hurt_small", &"enemy_hurt_large", &"enemy_death",
	&"pickup_gold", &"pickup_ore", &"pickup_echo", &"pickup_rune", &"pickup_relic", &"potion",
	&"ui_click", &"ui_hover", &"ui_confirm", &"ui_cancel", &"ui_error",
]


func after_each() -> void:
	AudioManager._missing_logged.clear()
	AudioManager._fade_target = null
	AudioManager._stopping = false
	AudioManager._fade_elapsed = 0.0
	AudioManager._fade_seconds = 1.0
	AudioManager._music_index = 0
	for player: AudioStreamPlayer in AudioManager._music_players:
		player.stop()
		player.stream = null
		player.volume_db = 0.0
	for player: AudioStreamPlayer in AudioManager._plain_pool:
		player.stop()
		player.queue_free()
	AudioManager._plain_pool.clear()
	for player: AudioStreamPlayer2D in AudioManager._positional_pool:
		player.stop()
		player.queue_free()
	AudioManager._positional_pool.clear()
	for bus: StringName in [&"Music", &"SFX", &"UI"]:
		var idx := AudioServer.get_bus_index(bus)
		if idx != -1:
			AudioServer.set_bus_volume_db(idx, 0.0)


## A real short click so the player stays `playing` through the whole test.
func _track() -> AudioStream:
	return SfxBank.make_click(440.0)


## A click that never ends, so a pooled player carrying it cannot finish part
## way through a test however slow the machine is between two statements.
## The bank's real `ui_click` is 1448 bytes (~16 ms), and a fill loop that
## outlasts it reuses an already-finished player instead of filling to the cap
## (`[15] expected to equal [16]`, the pre-G15a flake).
func _looping_click() -> AudioStreamWAV:
	var wav := SfxBank.make_click(440.0)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = wav.data.size() / 2
	return wav


## Fills the plain pool to `count` through the real acquire path, each player
## playing `stream`. Asserts every acquire grew the pool by one, so a stream
## that ended mid-fill is reported as the fixture failure it is rather than
## resurfacing as a cap failure.
func _fill_plain_pool(count: int, stream: AudioStream) -> void:
	for i in count:
		var player := AudioManager._acquire_plain()
		player.stream = stream
		player.play()
		assert_eq(AudioManager._plain_pool.size(), i + 1, "fixture: acquire %d grew the pool" % i)


# Crossfade state machine

func test_play_music_starts_a_fade_in() -> void:
	var track := _track()
	AudioManager.play_music(track, 1.0)
	var incoming: AudioStreamPlayer = AudioManager._music_players[1]
	assert_eq(AudioManager._fade_target, track, "the fade stores the incoming track")
	assert_eq(incoming.stream, track)
	assert_true(incoming.playing)
	assert_almost_eq(db_to_linear(incoming.volume_db), 0.0, 0.0001, "starts silent")
	AudioManager._tick_fades(0.5)
	assert_almost_eq(db_to_linear(incoming.volume_db), 0.5, 0.0001, "halfway through the fade")
	AudioManager._tick_fades(0.5)
	assert_almost_eq(db_to_linear(incoming.volume_db), 1.0, 0.0001, "full volume at the end")
	assert_eq(AudioManager._music_index, 1, "the incoming player becomes current")
	assert_null(AudioManager._fade_target, "fade finished")


func test_play_music_crossfades_between_the_two_players() -> void:
	var a := _track()
	var b := _track()
	AudioManager.play_music(a, 0.0)
	assert_eq(AudioManager._music_index, 1, "instant play leaves player 1 current")
	var out: AudioStreamPlayer = AudioManager._music_players[1]
	var inc: AudioStreamPlayer = AudioManager._music_players[0]
	AudioManager.play_music(b, 1.0)
	assert_eq(inc.stream, b)
	assert_true(inc.playing)
	assert_almost_eq(db_to_linear(out.volume_db), 1.0, 0.0001, "old track at full before the fade")
	assert_almost_eq(db_to_linear(inc.volume_db), 0.0, 0.0001, "new track starts silent")
	AudioManager._tick_fades(0.5)
	assert_almost_eq(db_to_linear(out.volume_db), 0.5, 0.0001, "old track fades out")
	assert_almost_eq(db_to_linear(inc.volume_db), 0.5, 0.0001, "new track fades in")
	AudioManager._tick_fades(0.5)
	assert_false(out.playing, "old track stops once the crossfade completes")
	assert_almost_eq(db_to_linear(inc.volume_db), 1.0, 0.0001)
	assert_eq(AudioManager._music_index, 0, "current flips to player 0")
	assert_null(AudioManager._fade_target)


func test_play_music_switches_instantly_when_fade_is_zero() -> void:
	var a := _track()
	var b := _track()
	AudioManager.play_music(a, 0.0)
	AudioManager.play_music(b, 0.0)
	assert_eq(AudioManager._music_players[0].stream, b)
	assert_true(AudioManager._music_players[0].playing)
	assert_false(AudioManager._music_players[1].playing, "previous player stopped instantly")
	assert_null(AudioManager._fade_target)


func test_stop_music_fades_out_then_stops() -> void:
	AudioManager.play_music(_track(), 0.0)
	var current: AudioStreamPlayer = AudioManager._music_players[1]
	assert_true(current.playing)
	AudioManager.stop_music(0.5)
	assert_true(AudioManager._stopping)
	AudioManager._tick_fades(0.25)
	assert_almost_eq(db_to_linear(current.volume_db), 0.5, 0.0001)
	assert_true(current.playing, "still audible halfway through the stop fade")
	AudioManager._tick_fades(0.25)
	assert_false(current.playing, "stopped once the fade completes")
	assert_false(AudioManager._stopping)


func test_stop_music_is_instant_when_fade_is_zero() -> void:
	AudioManager.play_music(_track(), 0.0)
	AudioManager.stop_music(0.0)
	assert_false(AudioManager._music_players[1].playing)
	assert_null(AudioManager._fade_target)
	assert_false(AudioManager._stopping)


func test_stop_music_stops_everything_and_leaves_no_stale_fade() -> void:
	AudioManager.play_music(_track(), 1.0)  # a crossfade is in progress
	AudioManager.stop_music(0.25)
	AudioManager._tick_fades(0.25)
	for player: AudioStreamPlayer in AudioManager._music_players:
		assert_false(player.playing, "every music player stops after the stop fade")
	assert_false(AudioManager._stopping)
	assert_null(AudioManager._fade_target, "no stale crossfade survives a stop")
	AudioManager._tick_fades(1.0)
	for player: AudioStreamPlayer in AudioManager._music_players:
		assert_false(player.playing, "later ticks do not restart a stopped track")


# SFX pooling

func test_plain_pool_reuses_an_idle_player() -> void:
	var first: AudioStreamPlayer = AudioManager._acquire_plain()
	assert_eq(AudioManager._plain_pool.size(), 1)
	var second: AudioStreamPlayer = AudioManager._acquire_plain()
	assert_eq(second, first, "an idle player is reused instead of growing the pool")
	assert_eq(AudioManager._plain_pool.size(), 1)


func test_plain_pool_grows_while_players_are_busy() -> void:
	var first: AudioStreamPlayer = AudioManager._acquire_plain()
	first.stream = SfxBank.make_click(440.0)
	first.play()
	var second: AudioStreamPlayer = AudioManager._acquire_plain()
	assert_ne(second, first, "a busy player is not reused")
	assert_eq(AudioManager._plain_pool.size(), 2)


func test_plain_pool_respects_the_cap() -> void:
	var cap: int = AudioManager.SFX_POOL_CAP
	var looping := _looping_click()
	_fill_plain_pool(cap, looping)
	assert_eq(AudioManager._plain_pool.size(), AudioManager.SFX_POOL_CAP)
	for player: AudioStreamPlayer in AudioManager._plain_pool:
		assert_true(player.playing, "fixture: the looping click keeps every pooled player playing")
	var oldest: AudioStreamPlayer = AudioManager._plain_pool[0]
	AudioManager.play_sfx(&"ui_click", Vector2.INF, 0.0)
	assert_eq(AudioManager._plain_pool.size(), AudioManager.SFX_POOL_CAP, "the cap holds; the oldest player is stolen")
	assert_eq(AudioManager._plain_pool[0], oldest, "the stolen player is the oldest in the pool")
	assert_ne(oldest.stream, looping, "the stolen player carries the new stream")


func test_plain_pool_reclaims_a_stopped_player() -> void:
	var cap: int = AudioManager.SFX_POOL_CAP
	_fill_plain_pool(cap, _looping_click())
	assert_eq(AudioManager._plain_pool.size(), cap, "fixture: the pool is full, so it cannot grow")
	var victim: AudioStreamPlayer = AudioManager._plain_pool[3]
	victim.stop()
	assert_false(victim.playing, "fixture: a stopped player is idle")
	var reused := AudioManager._acquire_plain()
	assert_eq(reused, victim, "an idle player is reclaimed rather than the pool growing")
	assert_eq(AudioManager._plain_pool.size(), cap, "reclaiming does not grow the pool")


func test_positional_sfx_uses_a_separate_pool_and_position() -> void:
	AudioManager.play_sfx(&"hit_light", Vector2(120, 80), 0.0)
	assert_eq(AudioManager._plain_pool.size(), 0, "positional sfx never touch the plain pool")
	assert_eq(AudioManager._positional_pool.size(), 1)
	var player: AudioStreamPlayer2D = AudioManager._positional_pool[0]
	assert_eq(player.global_position, Vector2(120, 80))
	assert_true(player.playing)
	assert_eq(player.get_parent(), AudioManager._sfx_root, "positional players live under the sfx root")


func test_play_sfx_uses_the_bank_stream() -> void:
	var expected: AudioStream = AudioManager._bank.get_stream(&"hit_light")
	assert_not_null(expected, "precondition: the bank maps hit_light")
	AudioManager.play_sfx(&"hit_light", Vector2.INF, 0.0)
	assert_eq(AudioManager._plain_pool[0].stream, expected, "the player carries the bank's stream")


func test_missing_id_plays_placeholder_and_logs_once() -> void:
	var placeholder: AudioStream = AudioManager._bank.get_stream(&"placeholder_click")
	assert_not_null(placeholder)
	AudioManager.play_sfx(&"does_not_exist", Vector2.INF, 0.0)
	assert_eq(AudioManager._plain_pool[0].stream, placeholder, "missing id plays the placeholder click")
	assert_true(AudioManager._missing_logged.has(&"does_not_exist"))
	AudioManager.play_sfx(&"does_not_exist", Vector2.INF, 0.0)
	assert_eq(AudioManager._missing_logged.size(), 1, "a repeated missing id is not logged again")


func test_pitch_variance_zero_is_deterministic() -> void:
	AudioManager.play_sfx(&"ui_click", Vector2.INF, 0.0)
	assert_eq(AudioManager._plain_pool[0].pitch_scale, 1.0)


func test_pitch_variance_stays_in_bounds() -> void:
	AudioManager.play_sfx(&"ui_click", Vector2.INF, 0.1)
	var pitch: float = AudioManager._plain_pool[0].pitch_scale
	assert_true(pitch >= 0.9 - 0.0001 and pitch <= 1.1 + 0.0001, "pitch stays within +-10%%")


# Bus volume mapping

func test_ready_creates_the_four_buses() -> void:
	for bus: StringName in [&"Master", &"Music", &"SFX", &"UI"]:
		assert_ne(AudioServer.get_bus_index(bus), -1, "%s bus exists" % bus)


func test_set_bus_volume_maps_linear_to_db() -> void:
	AudioManager.set_bus_volume(&"Music", 0.5)
	var idx := AudioServer.get_bus_index(&"Music")
	assert_almost_eq(AudioServer.get_bus_volume_db(idx), linear_to_db(0.5), 0.0001)


func test_set_bus_volume_clamps_to_unit() -> void:
	var idx := AudioServer.get_bus_index(&"Music")
	AudioManager.set_bus_volume(&"Music", 2.0)
	assert_almost_eq(AudioServer.get_bus_volume_db(idx), linear_to_db(1.0), 0.0001, "clamped at 1.0")
	AudioManager.set_bus_volume(&"Music", -0.5)
	assert_almost_eq(AudioServer.get_bus_volume_db(idx), linear_to_db(0.0), 0.0001, "clamped at 0.0")


func test_set_bus_volume_unknown_bus_is_ignored() -> void:
	AudioManager.set_bus_volume(&"NotABus", 0.5)  # must not crash
	assert_eq(AudioServer.get_bus_index(&"NotABus"), -1)


# SfxBank data

func test_audio_manager_loaded_the_bank() -> void:
	assert_not_null(AudioManager._bank, "AudioManager loads SfxBank at startup")
	if AudioManager._bank != null:
		assert_true(AudioManager._bank.has_id(&"hit_light"))


func test_sfx_bank_tres_loads_and_covers_every_week_two_id() -> void:
	var bank := load("res://data/audio/sfx_bank.tres") as SfxBank
	assert_not_null(bank, "SfxBank loads from data/audio")
	if bank == null:
		return
	for id: StringName in WEEK2_SFX_IDS:
		assert_true(bank.has_id(id), "%s mapped in the bank" % id)
		assert_not_null(bank.get_stream(id), "%s placeholder loads headless" % id)


func test_sfx_bank_includes_a_placeholder_click() -> void:
	var bank := load("res://data/audio/sfx_bank.tres") as SfxBank
	assert_not_null(bank)
	if bank == null:
		return
	assert_true(bank.has_id(&"placeholder_click"))
	assert_not_null(bank.get_stream(&"placeholder_click"))
