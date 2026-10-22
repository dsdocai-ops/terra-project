# Credits

Every third-party asset under `assets/` (anything not produced by `tools/art/build_all.py` or `tools/audio/build_sfx.py`), and every third-party font under `addons/`, has one row here, added in the same commit as the file. One row per file, or per family or pack with a path glob. Allowed licenses: CC0, CC-BY 3.0/4.0, OFL, or an explicit free-for-commercial-use license. See `specs/SPEC-art-audio.md`, "Sourced assets". `tests/integration/test_credits.gd` checks this table against `assets/`.

| Asset path | Source URL | Author | License | License URL | Modifications |
|---|---|---|---|---|---|
| `addons/gut/fonts/AnonymousPro-*.ttf` | https://github.com/bitwes/Gut | Mark Simonson | OFL 1.1 | http://scripts.sil.org/OFL | none; ships inside the GUT 9.7.1 test addon, not used by game scenes |
| `addons/gut/fonts/CourierPrime-*.ttf` | https://github.com/bitwes/Gut | Alan Dague-Greene, Quote-Unquote Apps | OFL 1.1 | http://scripts.sil.org/OFL | none; ships inside the GUT 9.7.1 test addon, not used by game scenes |
| `addons/gut/fonts/LobsterTwo-*.ttf` | https://github.com/bitwes/Gut | Pablo Impallari | OFL 1.1 | http://scripts.sil.org/OFL | none; ships inside the GUT 9.7.1 test addon, not used by game scenes |
| `addons/gut/source_code_pro.fnt` | https://github.com/bitwes/Gut | Paul D. Hunt, Adobe (Source Code Pro; inferred from the file name, the resource carries no font metadata) | OFL 1.1 | http://scripts.sil.org/OFL | rasterized to a Godot BitmapFont resource by the GUT authors; ships inside the GUT 9.7.1 test addon, not used by game scenes |
