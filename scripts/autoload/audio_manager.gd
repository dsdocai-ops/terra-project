extends Node
## Music crossfades and pooled SFX. Owned by art-audio (week 2 fills it in).
## Week 1 stub: API shape from SPEC-art-audio.
## Sync: none, presentation only; each peer plays from local state.

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"
const BUS_UI: StringName = &"UI"


## Crossfades to `track` over `fade_seconds` on two music players.
func play_music(_track: AudioStream, _fade_seconds: float = 1.5) -> void:
	pass


## Pooled AudioStreamPlayer2D when `pos` is given, non-positional otherwise.
## Unknown ids log once and play a placeholder click.
func play_sfx(_id: StringName, _pos: Vector2 = Vector2.INF, _pitch_variance: float = 0.1) -> void:
	pass


func set_bus_volume(_bus: StringName, _linear: float) -> void:
	pass


func stop_music(_fade_seconds: float) -> void:
	pass
