extends SceneTree
## Generates the week-2 placeholder SFX (SPEC-art-audio, placeholder-first):
## a short generated click under assets/audio/sfx/<id>.wav for every id in
## SFX_IDS, then writes data/audio/sfx_bank.tres mapping each id to its file.
## Godot loads WAV natively (BRIEF Assumption 9); the tools/audio/ synth
## pipeline replaces these files in W2-B7 and later. Idempotent: re-running
## rewrites the same files. Sourced files never appear here.
## Run: godot --headless --path . -s tools/make_placeholder_sfx.gd

const SFX_IDS: Array[StringName] = [
	&"hit_light", &"hit_heavy", &"crit", &"dodge", &"perfect_dodge",
	&"enemy_hurt_small", &"enemy_hurt_large", &"enemy_death",
	&"pickup_gold", &"pickup_ore", &"pickup_echo", &"pickup_rune", &"pickup_relic", &"potion",
	&"ui_click", &"ui_hover", &"ui_confirm", &"ui_cancel", &"ui_error",
	&"placeholder_click",
]
const OUT_DIR := "res://assets/audio/sfx"
const BANK_DIR := "res://data/audio"
const BANK_PATH := "res://data/audio/sfx_bank.tres"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BANK_DIR))
	var bank := SfxBank.new()
	for id: StringName in SFX_IDS:
		var path := "%s/%s.wav" % [OUT_DIR, id]
		_write_wav(path, SfxBank.make_click(_tone_for(id)))
		bank.entries[id] = path
	var err := ResourceSaver.save(bank, BANK_PATH)
	print("[make_placeholder_sfx] wrote %d placeholder clicks and %s (save err %d)" % [SFX_IDS.size(), BANK_PATH, err])
	quit(0 if err == OK else 1)


## A stable per-id base frequency so no two placeholder clicks are identical.
func _tone_for(id: StringName) -> float:
	var name := str(id)
	var total := 0
	for i in name.length():
		total += name.unicode_at(i)
	return 440.0 + float(total % 240)


## Writes an AudioStreamWAV as a 16-bit mono PCM .wav (RIFF header + fmt + data).
func _write_wav(path: String, wav: AudioStreamWAV) -> void:
	var bytes := wav.data
	var data_size := bytes.size()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + data_size)
	file.store_buffer("WAVE".to_ascii_buffer())
	file.store_buffer("fmt ".to_ascii_buffer())
	file.store_32(16)  # fmt chunk size
	file.store_16(1)  # PCM
	file.store_16(1)  # mono
	file.store_32(wav.mix_rate)
	file.store_32(wav.mix_rate * 2)  # byte rate
	file.store_16(2)  # block align
	file.store_16(16)  # bits per sample
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data_size)
	file.store_buffer(bytes)
	file.close()
