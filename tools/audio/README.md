# tools/audio

Generated SFX and chiptune music. The contract (SFX list, loudness targets, music tracks, review step) is [SPEC-art-audio.md](../../specs/SPEC-art-audio.md), sections "SFX" and "Music". Dev-only: the game never runs Python.

| Path | What it is |
|---|---|
| `sfx/<id>.json` | One sfxr-style parameter dict per SFX id (waveform, ADSR, pitch slide, vibrato, low-pass, bit-crush) |
| `music/<id>.json` | One pattern file per generated track (two square, one triangle, one noise channel), with its brief: tempo, key, instrumentation |

Both folders are empty in week 1. Placeholder SFX come from `AudioManager`'s placeholder click.

## Planned tools (W2-B7 and later)

| File | What it will do |
|---|---|
| `synth.py` | Renders an SFX parameter dict to 44.1 kHz mono |
| `build_sfx.py` | Renders every `sfx/*.json` to `assets/audio/sfx/<id>.ogg`, normalized to -16 LUFS short-term, peak -1 dBFS |
| `tracker.py` | Renders `music/*.json` to OGG loops, 60 to 120 s, -14 LUFS integrated |
| `review_sheet.py` | Waveform and spectrogram PNG per batch for the review step |
| `tests/` | pytest: synth envelope, loudness, deterministic output |

The OGG encoder dependency (`soundfile` plus `ffmpeg`, or a pure-Python encoder) is an open question in SPEC-art-audio, decided when `synth.py` lands.

Sourced audio (water, fire, stone, crowd, and any CC0 music) does not live here: it goes straight to `assets/audio/` with a row in `CREDITS.md`.
