# Spec: relics

| | |
|---|---|
| Module id | `relics` |
| Owner | Dev B |
| Weeks | 4 (RelicData, Shrine, 20 relics, active slot), 8 (40 relics total, synergies), 11 (all 88, Cursed Altars, second active slot, Relic Vault data) |
| Design doc | section 9 (9.1 to 9.4), section 13 (Relic Vault), section 14 (Abyssal Attunement, Curse Breaker, Safe Line, Lucky Find) |
| Depends on | `effect-system`, `run-economy` |
| Depended on by | `ui-hud`, `town` (Relic Vault), `bosses` (Hollow You snapshot), `endgame` (codex) |

## Objective

All 88 relics from the design doc as data files plus small effect scripts, the Shrine choice flow, active relics on C and B, cursed relics from Cursed Altars, and the 12 tag synergies, with every relic covered by the trigger harness and testable in co-op.

## Scope

### Counts (locked)

| Group | Count | Design doc |
|---|---|---|
| Passive, On Dodge | 6 | 9.1 nos. 1 to 6 |
| Passive, On Hit | 8 | 7 to 14 |
| Passive, On Kill | 6 | 15 to 20 |
| Passive, On Getting Hit | 5 | 21 to 25 |
| Passive, Crit | 5 | 26 to 30 |
| Passive, Elemental | 7 | 31 to 37 |
| Passive, Ability | 5 | 38 to 42 |
| Passive, Movement and Position | 4 | 43 to 46 |
| Passive, Economy and Exploration | 5 | 47 to 51 |
| Passive, Transformation (Legendary) | 13 | 52 to 64 |
| Passive, Extra tag fillers | 6 | 65 to 70 |
| Active (C / B) | 10 | 9.2 |
| Cursed | 8 | 9.3 |
| **Total** | **88** | |

Every relic name, effect text, and group is exactly as written in design doc section 9. The `.tres` `display_name` and `description` are copied from there; balance numbers in the description are the source of truth for the effect script's constants.

### Week batches

- Week 4 (20): On Dodge 1 to 6, On Hit 7 to 14, On Kill 15 to 20. These exercise `player_dodged`, `hit_landed`, `enemy_killed`.
- Week 8 (+20 = 40): On Getting Hit, Crit, Elemental, Ability (21 to 42) minus two, plus Bomb Bag and Healing Totem as the first actives; all 12 synergies live.
- Week 11 (+48 = 88): everything else, Cursed Altars, Abyssal Attunement second slot.

### RelicData

```gdscript
class_name RelicData extends ContentData
enum Rarity { COMMON, RARE, EPIC, LEGENDARY, CURSED }
@export var rarity: Rarity
@export var kind: Kind                    # PASSIVE, ACTIVE, CURSED
@export var description: String           # from design doc, with {value} placeholders filled by effect constants
@export var icon: Texture2D
@export var effect_script: GDScript       # extends Effect
@export var tags: Array[StringName]       # 1 to 2 from Tags vocabulary (inherited from ContentData)
@export var max_stacks: int = 1           # duplicates allowed? Lucky Coin stacks, Second Wind does not
@export var active_cooldown: float        # actives only
@export var active_charges: int           # Bomb Bag 3
@export var weight: float = 1.0           # drop weight within rarity
```

Rarity weights for Shrine rolls: common 60, rare 28, epic 10, legendary 2, adjusted by `Stat.LUCK` and Lucky Find (+5%/rank shift to higher tiers). Cursed never roll at Shrines. Transformation relics are all Legendary.

### Shrine flow

`SHRINE` populator spawns a `Shrine` interactable. Interact (host validates one use per player per shrine) rolls 3 relics the player does not already hold at max stacks and sends `relic_choice_offered(peer_id, ids)`; `ui-hud` shows the popup; `request_pick_relic(index)`; host attaches via `EffectHost.add`, emits `relic_picked`, updates codex. Gambler's Die rerolls the next shrine's 3. Shrines also host ability swap (`abilities` adds its own interactable to the same room). Merchant shops and Treasure chests use the same roll helper `RelicRoller.roll(player, count, allow_cursed)`.

Relic Vault starting pick (`town`): a chosen common relic attached at run start. Pit Pact: random legendary at every floor start. Chaos Engine: random legendary effect per room, detached on room exit.

### Active relics

Slot 1 on `relic_active_1` (C), slot 2 on `relic_active_2` (B) after Abyssal Attunement. Active relics are `Effect`s with `activate()`; charges refill per room where stated; cooldown shown on HUD. Picking an active when slots are full offers replace-or-skip. Lantern of Souls stores the last elite's affix as a one-shot.

### Cursed relics and Cursed Altars

`CURSED_ALTAR` populator spawns an altar with 1 cursed relic (2 with Greed Chain visible). Taking it attaches the effect and its downside. Curse Breaker node (once per run) removes the downside half. Doomed synergy (2 cursed) halves downsides. Cursed relics count toward Transformation-like "run-defining" display on the HUD.

### Synergies

`SynergyData`: `id`, `display_name`, `tag`, `required_count` (3; Elementalist 1 each of 4 element tags; Doomed 2 cursed), `effect_script`, `description`. On every `relic_picked` / `relic_removed`, `SynergyTracker` recomputes counts from `EffectHost.list_tags()`, attaches or detaches synergy effects, emits `synergy_activated`, and exposes progress for the HUD. Data-driven test asserts each synergy's tag appears on at least 4 relics (design doc rule).

| Synergy | Requirement | Relics carrying the tag (must be >= 4) |
|---|---|---|
| Pyromaniac | 3 fire | Ember Boots, Kindling, Ember Heart, Volatile Core, Glass Cannonball (explosions tagged fire), Prism |
| Glacial | 3 frost | Frostwalkers, Permafrost, Panic Button, Frost Fang, Prism |
| Thunderstruck | 3 storm | Storm Sandals, Spark Plug, Lightning Rod, Thunder Bell |
| Plaguebringer | 3 poison | Venom Gland, Plague Doctor's Mask, Rot Lung, Acid Flask |
| Nightblade | 3 shadow | Assassin's Mark, Shadow Ink, Night Cowl, Ghost Wrap |
| Phantom Dancer | 3 dodge | Ember Boots, Storm Sandals, Mirror Step, Frostwalkers, Ghost Wrap, Rebound Spring |
| Reaper | 3 crit | Lucky Coin, Glass Cannonball, Assassin's Mark, Jackpot, Fracture Lens |
| Arcanist | 3 ability | Overcharger, Spellweaver, Rune Battery, Echo Rune, Big Brain |
| Juggernaut | 3 on_damaged | Thorn Mail, Panic Button, Spite Totem, Cracked Shell, Revenge Pact |
| Gold Fever | 3 economy | Miner's Luck, Ore Magnet, Treasure Map, Merchant's Badge, Echo Collector, Golden Idol |
| Elementalist | 1 relic each of 4 different elements | any element-tagged |
| Doomed | 2 cursed | all 8 cursed |

Final tag assignment per relic is made in the `.tres` files in week 4/8 and verified by the >= 4 test; the table above is the starting assignment.

### Codex

Every relic seen (offered or picked) is added to `profile.codex.relics`; Relic Vault in town lists them with descriptions and lets the player choose the run-start common.

## Interfaces provided

`RelicData`, `SynergyData`, `RelicRoller`, `Shrine`, `CursedAltar`, `SynergyTracker` (`progress(player) -> Array[{synergy, count, required, active}]`), `ActiveRelicController` (`activate(slot)`, `cooldown_fraction(slot)`), build snapshot `relics_of(player) -> Array[{id, stacks}]` for Hollow You.

## Interfaces consumed

- `effect-system`: `Effect`, `EffectHost`, `Tags`, harness.
- `run-economy`: `RunPlayerState.relics`, shop stock, Luck.
- `floor-generation`: populators for `SHRINE`, `CURSED_ALTAR`.
- `ui-hud`: choice popup, HUD icons and synergy panel.
- `save-system`: codex.

## Data model

`data/relics/<id>.tres` + `scripts/effects/relics/<id>.gd`. `data/synergies/<id>.tres` + `scripts/effects/synergies/<id>.gd`. Icons placeholder: colored square with first letter until `art-audio`.

## Multiplayer ownership

Rolls, picks, attaches, actives, synergy evaluation: host. `request_pick_relic`, `request_activate_relic(slot)`, `request_take_cursed` from clients. HUD state from replicated `RunPlayerState`.

Sync: host-authoritative.

## Testing

- Data-driven `test_relic_data.gd`: 88 files, ids match filenames, each has rarity, kind, 1 to 2 tags, description non-empty, effect script extends `Effect`, every synergy tag on >= 4 relics, Transformation group all Legendary, cursed only `CURSED` rarity.
- Harness `test_relic_triggers.gd`: one case per relic (88) asserting the trigger fires the documented result once (e.g. Ember Boots spawns a fire trail on `player_dodged`; Echo Blade's 4th hit deals a second hit; Second Wind sets `prevented` once per run). Stack cases for stackable relics.
- `test_synergies.gd`: each activates at threshold, deactivates on removal, Elementalist and Doomed special rules.
- `test_relic_roller.gd`: rarity distribution over 10 000 rolls within 2% of weights, Luck shift, no duplicates past `max_stacks`, no cursed at shrines.
- Two-instance: client picks at shrine; host confirms; HUD and synergy panel update on both; active relic use visible to both.

## Success criteria

- [ ] Week 4: 20 relics, Shrine flow, active slot, all with harness tests, in co-op.
- [ ] Week 8: 40 relics, all 12 synergies active with HUD progress.
- [ ] Week 11: 88 relics, Cursed Altars, second active slot, Relic Vault pick, codex.
- [ ] Zero relics implemented by editing combat or enemy code; all through `Effect`.
- [ ] "Every relic gets a quick test: does it trigger, does it stack, does it work in co-op" (design doc 23) satisfied by harness + co-op checklist in weekly notes.

## Open questions

- Final tag assignments for Pyromaniac to reach 4 fire relics; candidates listed above, settled in the `.tres` files in week 8.
