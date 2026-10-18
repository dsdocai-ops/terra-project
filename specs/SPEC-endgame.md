# Spec: endgame

| | |
|---|---|
| Module id | `endgame` |
| Owner | Dev B |
| Weeks | 11 (Deep Mode, Heat levels, Daily Dive, achievements, codex completion) |
| Design doc | section 15, section 11 (Keeper ending), section 13 (Bounty Board, Wardrobe), section 20 (week 11) |
| Depends on | `bosses`, `story-dialogue`, `progression-trees`, `save-system` |
| Depended on by | `town` (Wardrobe cosmetics, Tavern daily board), `ui-hud` (achievements, codex) |

## Objective

Reasons to keep diving after the credits: Deep Mode, ten stackable Heat modifiers, a seeded Daily Dive with a leaderboard, 50+ achievements that unlock cosmetics and characters, and a complete codex.

## Scope

### Deep Mode

Unlocked by any ending (`ending.*`). Toggle in Run Setup. Effects: every boss gains its `deep_mode_phase`; enemies get +1 random attack pattern from a per-biome extra pool (`EnemyData.deep_attacks`, authored by `biomes`/`enemies-ai` in week 11); loot rarity +1 tier shift; Echo Shards x1.5. If `ending.keeper` is set, **The Keeper** (the player's dark version, a Hollow You variant using the profile's most-played class and best-known build from `profile.stats`) appears as an extra boss on a random floor 3 of biomes 2 to 5.

### Heat levels

10 stackable `HeatModifier` Resources selected in Run Setup (any subset); each adds an Echo Shard multiplier (+10% to +25%) and a `Effect`-style modifier attached to the run:

| Heat | Effect |
|---|---|
| Swift | enemies +20% move and attack speed |
| Parched | healing -50% |
| Infested | elites everywhere: elite chance x3 |
| Relentless | bosses gain their `heat_phase` (4th phase) |
| Frail | player max HP -30% |
| Hoarder | shops +100% price |
| Volatile | all enemies explode on death |
| Blind | darkness modifier on every floor |
| Famine | potions -1 slot, min 1 |
| Cursed Ground | every floor starts with a random cursed relic offered, decline costs 10% HP |

Heat is applied on the host for all players; the party agrees in the lobby (host picks, clients see).

### Daily Dive

Seed = hash of UTC date + salt; fixed character/class/weapons/heat for the day (rolled from the seed among unlocked-at-start content so everyone can play it). One attempt per day per profile. Score = floors cleared x 1000 + kills + Echo Shards x 10 + extraction bonus. Local leaderboard in profile (`daily_dive_best`, last 30 days). Online leaderboard: optional HTTP POST/GET to a tiny endpoint if one exists by week 11; otherwise local only and a "share code" string (seed + score + build) that can be pasted. The design doc says "local or online"; local is the guaranteed deliverable.

### Achievements

50+ `AchievementData` (`id`, `title`, `description`, `condition` evaluated from `Events` and profile stats, `reward: cosmetic id or character flag`, `hidden`). Categories: progression (first extraction, each biome boss, each ending), mastery (each class to 5 and 10), content (all relics seen, all abilities, all lore), challenge (no-hit boss, floor 30 with 3 cursed relics, extract with 10 000 gold, Hollow You beaten with your own build), co-op (4-player extraction, revive 10 teammates), secret bosses. Toast on unlock; list in `ui-hud`. Writes `achievements` and `cosmetics_unlocked`. Kestrel "Reach Biome 4" and Ivy lanterns are story flags but also mirrored as achievements.

### Codex completion

`Codex` aggregates seen ids across relics, abilities, enemies, bosses, lore; shows percent per category and total; 100% is an achievement with a Wardrobe reward.

## Interfaces provided

`HeatModifier`, `AchievementData`, `AchievementTracker`, `DailyDive` (`today_setup()`, `submit(result)`, `leaderboard()`), `DeepMode` flags read by `bosses`/`enemies-ai`/`run-economy` through `RunState.deep_mode` and `RunState.heat: Array[StringName]`.

## Interfaces consumed

- `bosses`: `deep_mode_phase`, `heat_phase`, Keeper variant via Hollow You snapshot API.
- `story-dialogue`: ending flags.
- `progression-trees`, `run-economy`: Echo Shard multipliers, shop prices, potion slots.
- `save-system`: profile fields.
- `town`, `ui-hud`: Run Setup toggles, Tavern board, achievements screen, Wardrobe.
- `floor-generation`: forced Darkness modifier.

## Data model

`data/endgame/heat/<id>.tres` + effects, `data/endgame/achievements/<id>.tres`, `data/endgame/deep_attacks/` (owned by `enemies-ai` data).

## Multiplayer ownership

Deep Mode and Heat chosen by host, replicated in `RunState`. Achievements evaluated per player on the host and sent in `run_summary`. Daily Dive is solo only (leaderboard fairness); co-op lobby hides it.

Sync: host-authoritative run flags; per-player achievement gains.

## Testing

- Data-driven `test_endgame_data.gd`: 10 heat modifiers with multipliers, >= 50 achievements with valid rewards and unique ids, every cosmetic referenced exists.
- Unit `test_heat.gd`: multiplier stacking, each modifier's effect through the harness.
- Unit `test_daily_dive.gd`: same date gives same setup, one attempt per day, score formula, 30-day trimming.
- Unit `test_achievements.gd`: each condition fires from fake events/profile; hidden stays hidden until unlocked.
- Manual: Deep Mode run with Keeper appearing after a Keeper ending.

## Success criteria

- [ ] Week 11: Deep Mode with extra boss phases and Keeper variant, 10 Heat levels, Daily Dive with local leaderboard and share code, 50+ achievements with toasts and Wardrobe rewards, codex percentages.
- [ ] Heat x10 run is beatable in principle (playtest note), Echo multiplier totals shown in Run Setup.

## Open questions

- Online leaderboard endpoint: only if trivially available by week 11; local is the commitment.
