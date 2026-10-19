extends Node
## Music crossfades on two players, pooled SFX (positional and non-positional),
## and bus volume mapping (SPEC-art-audio). Owned by art-audio.
## Sync: none, presentation only; each peer plays from local state. Time
## effects never change pitch (SPEC-art-audio).
##
## The four buses (Master/Music/SFX/UI) are ensured at _ready: the spec names
## them and a default bus layout file is not in the repo, so the buses are
## created on the AudioServer if missing (idempotent, no project.godot edit).

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"
const BUS_UI: StringName = &"UI"

const MUSIC_PLAYER_COUNT := 2
const SFX_POOL_CAP := 16
const SFX_BANK_PATH := "res://data/audio/sfx_bank.tres"
const PLACEHOLDER_CLICK_ID: StringName = &"placeholder_click"
## Buses in order; the audio layout provides these (Master always exists).
const BUSES: Array[StringName] = [BUS_MASTER, BUS_MUSIC, BUS_SFX, BUS_UI]
## Missing ids are logged once each; past this the log is reset so a flood of
## unknown ids (e.g. a missing bank) cannot spam the console.
const MAX_MISSING_LOGS := 24

var _music_players: Array[AudioStreamPlayer] = []
## Index into _music_players of the currently audible player when idle.
var _music_index := 0
## Stream being faded to; null when no crossfade is running.
var _fade_target: AudioStream = null
var _fade_seconds := 1.0
var _fade_elapsed := 0.0
var _fade_from_linear := 1.0
## True while stop_music is fading the current player out.
var _stopping := false

var _plain_pool: Array[AudioStreamPlayer] = []
var _positional_pool: Array[AudioStreamPlayer2D] = []
var _sfx_root: Node2D
var _bank: SfxBank = null
var _builtin_click: AudioStreamWAV = null
var _missing_logged: Dictionary[StringName, bool] = {}


func _ready() -> void:
	_ensure_buses()
	for i in MUSIC_PLAYER_COUNT:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_MUSIC
		add_child(player)
		_music_players.append(player)
	_sfx_root = Node2D.new()
	_sfx_root.name = "SfxRoot"
	add_child(_sfx_root)
	_builtin_click = SfxBank.make_click(660.0)
	if ResourceLoader.exists(SFX_BANK_PATH):
		_bank = load(SFX_BANK_PATH) as SfxBank


func _process(delta: float) -> void:
	_tick_fades(delta)


## Crossfades to `track` over `fade_seconds` on two music players. A fade of
## zero switches instantly.
func play_music(track: AudioStream, fade_seconds: float = 1.5) -> void:
	if track == null:
		return
	var target := _other_player()
	target.stream = track
	target.play()
	if fade_seconds <= 0.0:
		_current_player().stop()
		target.volume_db = linear_to_db(1.0)
		_music_index = (_music_index + 1) % MUSIC_PLAYER_COUNT
		_fade_target = null
		return
	_fade_target = track
	_fade_seconds = fade_seconds
	_fade_elapsed = 0.0
	_fade_from_linear = db_to_linear(_current_player().volume_db)
	target.volume_db = linear_to_db(0.0)


## Pooled AudioStreamPlayer2D when `pos` is given, non-positional otherwise.
## Unknown ids log once and play a placeholder click. `pitch_variance`
## randomizes pitch_scale around 1.0; time effects never change pitch.
func play_sfx(id: StringName, pos: Vector2 = Vector2.INF, pitch_variance: float = 0.1) -> void:
	var stream := _resolve_stream(id)
	if pos.x != INF:
		var player := _acquire_positional()
		player.stream = stream
		player.global_position = pos
		player.pitch_scale = 1.0 + randf_range(-absf(pitch_variance), absf(pitch_variance))
		player.play()
	else:
		var player := _acquire_plain()
		player.stream = stream
		player.pitch_scale = 1.0 + randf_range(-absf(pitch_variance), absf(pitch_variance))
		player.play()


## Sets a bus to `linear` loudness (0.0 to 1.0), clamped. Unknown buses are
## ignored after a one-time warning.
func set_bus_volume(bus: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		_log_once(&"_bus_%s" % bus, "[audio] unknown bus %s" % bus)
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))


## Fades the current track out over `fade_seconds` then stops it. A fade of
## zero stops instantly. Stops every music player so a stop issued mid-
## crossfade cannot leave the incoming track playing.
func stop_music(fade_seconds: float) -> void:
	if fade_seconds <= 0.0:
		for player: AudioStreamPlayer in _music_players:
			player.stop()
		_stopping = false
		_fade_target = null
		return
	_stopping = true
	_fade_seconds = fade_seconds
	_fade_elapsed = 0.0
	_fade_from_linear = db_to_linear(_current_player().volume_db)
	_fade_target = null


## Advances the crossfade / stop fade by `delta`. Called from _process every
## idle frame; tests drive it directly so the state machine is deterministic.
func _tick_fades(delta: float) -> void:
	if _fade_target == null and not _stopping:
		return
	_fade_elapsed += delta
	var t := clampf(_fade_elapsed / _fade_seconds, 0.0, 1.0)
	if _stopping:
		var vol := linear_to_db(_fade_from_linear * (1.0 - t))
		for player: AudioStreamPlayer in _music_players:
			player.volume_db = vol
		if t >= 1.0:
			for player: AudioStreamPlayer in _music_players:
				player.stop()
			_stopping = false
			_fade_target = null
		return
	var from := _current_player()
	var to := _other_player()
	from.volume_db = linear_to_db(_fade_from_linear * (1.0 - t))
	to.volume_db = linear_to_db(t)
	if t >= 1.0:
		from.stop()
		_music_index = (_music_index + 1) % MUSIC_PLAYER_COUNT
		_fade_target = null


## First idle player in `pool`, or a new one up to SFX_POOL_CAP, or the oldest
## once the pool is full (a busy click is stolen rather than dropped).
func _acquire_plain() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _plain_pool:
		if not player.playing:
			return player
	if _plain_pool.size() < SFX_POOL_CAP:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		add_child(player)
		_plain_pool.append(player)
		return player
	return _plain_pool[0]


func _acquire_positional() -> AudioStreamPlayer2D:
	for player: AudioStreamPlayer2D in _positional_pool:
		if not player.playing:
			return player
	if _positional_pool.size() < SFX_POOL_CAP:
		var player := AudioStreamPlayer2D.new()
		player.bus = BUS_SFX
		_sfx_root.add_child(player)
		_positional_pool.append(player)
		return player
	return _positional_pool[0]


## The bank stream for `id`, else the placeholder click. Logs each unknown id
## once (SPEC-art-audio: "missing id logs once and plays a placeholder click").
func _resolve_stream(id: StringName) -> AudioStream:
	if _bank != null and _bank.has_id(id):
		var stream := _bank.get_stream(id)
		if stream != null:
			return stream
	_log_once(id, "[audio] unknown sfx id %s, playing placeholder" % id)
	return _placeholder_stream()


## The bank's placeholder_click file when present, else the code-built click.
func _placeholder_stream() -> AudioStream:
	if _bank != null:
		var stream := _bank.get_stream(PLACEHOLDER_CLICK_ID)
		if stream != null:
			return stream
	return _builtin_click


func _current_player() -> AudioStreamPlayer:
	return _music_players[_music_index]


func _other_player() -> AudioStreamPlayer:
	return _music_players[(_music_index + 1) % MUSIC_PLAYER_COUNT]


func _ensure_buses() -> void:
	for bus_name: StringName in BUSES:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


func _log_once(key: StringName, message: String) -> void:
	if _missing_logged.has(key):
		return
	_missing_logged[key] = true
	if _missing_logged.size() > MAX_MISSING_LOGS:
		_missing_logged.clear()
	push_warning(message)
