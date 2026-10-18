# Spec: save-system

| | |
|---|---|
| Module id | `save-system` |
| Owner | Dev B |
| Weeks | 5 |
| Design doc | section 18 "Saving", section 9.5 (what persists), section 12 (per-player progress) |
| Depends on | `foundation` |
| Depended on by | `run-economy`, `town`, `progression-trees`, `story-dialogue`, `classes-characters`, `endgame`, `ui-hud` (settings) |

## Objective

One JSON file per machine holding everything that survives a run, written at the moments the design doc lists, versioned so schema changes never lose a player's town.

## Scope

### What persists (`PlayerProfile`)

| Field | Owner module writes it |
|---|---|
| `save_version: int` | this module |
| `created_at`, `last_saved_at` | this module |
| `gold_banked: int`, `ore: Dictionary` (ore_id -> int), `echo_shards: int` | `run-economy` |
| `town: Dictionary` building_id -> level (0 to 3) | `town` |
| `skill_tree: Dictionary` node_id -> ranks, `respec_used_date` | `progression-trees` |
| `classes: Dictionary` class_id -> `{xp, mastery, tree: {node_id: ranks}, unlocked}` | `classes-characters`, `progression-trees` |
| `characters_unlocked: Array[String]` | `classes-characters` |
| `weapons_unlocked: Array[String]`, `weapon_damage_tiers: Dictionary` | `weapons`, `town` |
| `relic_vault_pick`, `rune_library_pick` | `town` |
| `potions: {slots, types, starting}` | `town` |
| `story_flags: Array[String]`, `lore_unlocked: Array[String]`, `endings_seen` | `story-dialogue` |
| `codex: {relics, abilities, enemies, bosses}` seen ids | `relics`, `abilities`, `enemies-ai`, `bosses` |
| `achievements: Array[String]`, `cosmetics_unlocked`, `equipped_cosmetics` | `endgame`, `town` |
| `rescued_miners: Array[String]` | `story-dialogue` |
| `map_room_deepest_rope: int` | `run-economy` |
| `deep_mode_unlocked`, `heat_levels_unlocked`, `daily_dive_best: Dictionary` | `endgame` |
| `stats: {runs, deaths, extractions, kills, deepest_floor, playtime_seconds}` | `run-economy` |
| `settings: {audio, video, screen_shake, bindings}` | `ui-hud` |

Runs are never saved mid-run. Quitting mid-run counts as death for currency rules.

### When it saves

`SaveManager.save()` is called by: `run-economy` on return to town (after banking), `town` and `progression-trees` after any purchase, `ui-hud` on settings change and on quit, `story-dialogue` when a flag that unlocks something is set. Debounced: multiple calls within one frame write once. Writes are atomic: write to `user://save.json.tmp`, then rename over `user://save.json`. Keep `user://save.bak` from the previous successful save.

### Loading and migration

On startup: read file, parse JSON, check `save_version`. If lower than current, run `migrations[version]` in order; each migration is a function `Dictionary -> Dictionary` in `scripts/autoload/save_migrations.gd`. If parse fails, load `save.bak`; if that fails, start fresh and keep the corrupt file as `save.corrupt.<timestamp>`. Missing keys get defaults from `PlayerProfile.defaults()` so new fields never need a migration unless semantics change.

### Co-op

Each machine saves its own profile. The host's town is the one visited together; at run end the host sends each client its per-player gains (`echo_shards`, `class_xp`, `story_flags` newly set, codex entries, achievements) via `run_summary(peer_id, gains)` and the client merges and saves. Gold and ore are split evenly and each banks their share.

## Interfaces provided

`SaveManager` autoload:

```gdscript
signal saved()
signal loaded(profile: PlayerProfile)

const SAVE_VERSION: int = 1
const PATH: String = "user://save.json"

var profile: PlayerProfile

func save() -> void                      # debounced, atomic
func load() -> void                      # on startup, migrates
func reset_profile() -> void             # new game, keeps settings
func export_debug() -> String            # JSON for debug console
```

`PlayerProfile` (RefCounted, not Resource, so it serializes cleanly): typed fields above, `to_dict()`, `static from_dict(d)`, `static defaults()`.

## Interfaces consumed

- `foundation`: autoload slot.
- `networking`: `run_summary` RPC is defined in `run-economy` and calls `SaveManager.profile` merge helpers here: `merge_run_gains(gains: Dictionary)`.

## Data model

JSON file. Example skeleton:

```json
{
  "save_version": 1,
  "gold_banked": 0,
  "ore": {"copper": 0, "iron": 0, "crystal": 0, "pearl": 0, "ember_ore": 0, "heartstone": 0},
  "echo_shards": 0,
  "town": {"blacksmith": 0, "alchemist": 0},
  "skill_tree": {},
  "classes": {"warrior": {"xp": 0, "mastery": 1, "tree": {}, "unlocked": true}},
  "story_flags": [],
  "settings": {"screen_shake": 1.0}
}
```

Content ids in the save are the `.tres` file names (`ContentData.id`); renaming a content file requires a migration.

## Multiplayer ownership

Local file per machine. Host never writes a client's profile. Sync: none beyond `run_summary` gains.

## Testing

- Unit `test_save_round_trip.gd`: `defaults()` to dict to JSON to dict to profile equals original; every field present.
- Unit `test_save_migrations.gd`: fixture files `tests/fixtures/save_v1.json` ... migrate to current and validate; fixture for each past version is added when a version bumps.
- Unit `test_save_recovery.gd`: corrupt file falls back to `.bak`; missing file starts fresh; settings survive `reset_profile`.
- Integration: save, quit, relaunch headless, profile equal.

## Success criteria

- [ ] Week 5: town upgrades, skill tree purchases, unlocks, and currencies survive restart.
- [ ] Atomic write verified by killing the process mid-save in a manual test; previous save intact.
- [ ] Schema change in any later week comes with a migration and a fixture (reviewed under "Ask first").
- [ ] Co-op client receives and saves its own gains after a shared run.

## Open questions

- Multiple profiles (slots) are not in the design doc; single profile. Revisit only if asked.
