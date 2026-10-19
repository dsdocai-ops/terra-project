class_name SfxBank
extends Resource
## Maps SFX ids (StringName) to files under assets/audio/sfx/ (SPEC-art-audio).
## Owned by art-audio. Sync: none (data).
##
## Placeholder-first: the week-2 ids point at short generated clicks from
## tools/make_placeholder_sfx.gd; the synth pipeline (tools/audio/, W2-B7)
## replaces the files later without touching this bank. get_stream loads
## lazily so a missing or unimported file degrades to null and AudioManager
## falls back to its builtin click.

@export var entries: Dictionary[StringName, String] = {}


func has_id(id: StringName) -> bool:
	return entries.has(id)


## Loads the AudioStream behind `id`, or null when unknown / not imported.
func get_stream(id: StringName) -> AudioStream:
	var path := entries.get(id, "") as String
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


## Builds a short decaying click as an AudioStreamWAV (44.1 kHz mono 16-bit).
## tools/make_placeholder_sfx.gd uses it to write the placeholder files and
## AudioManager uses it as its builtin fallback when the bank is missing.
## `freq_hz` varies per id so placeholder clicks are distinguishable.
static func make_click(freq_hz: float = 880.0) -> AudioStreamWAV:
	const SAMPLE_RATE := 44100
	const DURATION_SECONDS := 0.08
	const AMPLITUDE := 0.5
	var sample_count := int(SAMPLE_RATE * DURATION_SECONDS)
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / float(SAMPLE_RATE)
		var envelope := exp(-t * 55.0)
		var sample := sin(TAU * freq_hz * t) * envelope * AMPLITUDE
		pcm.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = pcm
	return wav
