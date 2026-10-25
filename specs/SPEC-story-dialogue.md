# Spec: story-dialogue

| | |
|---|---|
| Module id | `story-dialogue` |
| Owner | Dev B |
| Weeks | 6 (StoryManager, flags, dialogue system and UI, first NPCs, Act 1 beats), 7 (rescue missions), 10 (all NPC dialogue, Act 2 and 3, 3 endings, lore rooms, 40+ pages, character threads) |
| Design doc | section 11, section 4.1 (character unlocks), section 4.2 (class unlocks by rescue), section 10 (Lore Room, secret boss triggers, final boss phase 3), section 13 (NPC roles) |
| Depends on | `save-system`, `run-economy`, `enemies-ai` |
| Depended on by | `classes-characters` (unlock flags), `town` (NPC dialogue), `bosses` (final boss phase 3 choices, Watcher), `endgame` (Deep Mode Keeper variant), `ui-hud` (dialogue box, codex) |

## Objective

The story of Hollowmere told through flags, NPC dialogue that changes as the town and pit progress, lore pages, rescue missions, personal character events, and three endings, all authored as JSON that Claude writes and the team edits.

## Scope

### StoryManager

```gdscript
# StoryManager autoload
signal flag_set(flag: StringName)
signal lore_unlocked(page_id: StringName)
signal miner_rescued(miner_id: StringName)

func has_flag(flag: StringName) -> bool
func set_flag(flag: StringName) -> void             # idempotent, saves if flag is in UNLOCK_FLAGS
func flags() -> Array[StringName]
func act() -> int                                    # 1 to 3 derived from flags
func unlock_lore(page_id: StringName) -> void
func lore_unlocked_count() -> int
func evaluate(condition: Dictionary) -> bool          # dialogue condition language, below
func start_dialogue(dialogue_id: StringName, npc: Node = null) -> void
```

Flags are `StringName`s with a namespace: `story.foreman_defeated`, `story.act2_started`, `rescue.sly_nettie`, `char.ivy_unlocked`, `ending.seal`, `lore.vulkar_journal_3_read`, `town.blacksmith_2`, `secret.rat_king`, `boss.tide_king`. The canonical flag list lives in `data/dialogue/flags.json` and the data-driven test fails on any flag referenced in dialogue that is not declared.

### Dialogue data (JSON)

`data/dialogue/<npc_or_event>.json`:

```json
{
  "id": "mayor_hilde",
  "portrait": "res://assets/sprites/portraits/hilde.png",
  "entries": [
    {
      "id": "intro",
      "priority": 10,
      "conditions": {"all": [{"flag_not": "story.met_hilde"}]},
      "lines": [
        {"speaker": "Mayor Hilde", "text": "You're Wren's girl. Your father...", "emotion": "worried"},
        {"speaker": "Wren", "text": "...", "character_only": "wren"}
      ],
      "choices": [
        {"text": "What happened down there?", "goto": "intro_more"},
        {"text": "I'm going in.", "set_flags": ["story.met_hilde"], "end": true}
      ],
      "on_end": {"set_flags": ["story.met_hilde"], "give": {"gold": 50}}
    }
  ]
}
```

Condition language: `all`, `any`, `not`, `flag`, `flag_not`, `character` (current playable character id), `class`, `town_level {building, min}`, `ore_min`, `deepest_floor_min`, `rescued`, `act_min`, `random_chance`. The highest-priority entry whose conditions pass is the NPC's current dialogue; "talk again" shows the next passing entry or a fallback. Lines may be character-specific. Loaded at startup into `DialogueData` Resources (typed) with schema validation; a bad file fails the test suite, not the game.

Lore pages `data/lore/<page_id>.json`: `{id, title, body, biome, act, order}`.

### Dialogue UI

`DialogueBox` scene (`scenes/dialogue/`): portrait left, name, typewriter text (skippable), choices list, controller-friendly later. Pauses the local player's input, not the game (co-op). In co-op, town dialogue is per player (each talks to NPCs on their own screen); pit dialogue (rescue, lore) shows to all with the triggering player choosing.

#### DialogueBox mock-up — week 6, ready for Dev A feedback (W6-B2, PLAN G5)

`scenes/dialogue/dialogue_box.tscn` + `scripts/dialogue/dialogue_box.gd` are the working mock-up. Layout and behavior, per the spec line above; the visuals are placeholders drawn from `UiPalette` (parchment panel, bronze border, ink text). The W6-B6 theme art (portrait frame, name plate, choice buttons, typewriter blip) replaces the StyleBoxes without touching behavior.

- **Structure** (`CanvasLayer`, layer 20, hidden until a dialogue opens): `Root` (full-rect) → `Dim` (35% black, click-to-skip, consumes world clicks while open) and `Box` (bottom-center PanelContainer, 680 px) → portrait `TextureRect` (96x96, hidden when the dialogue declares no portrait), name plate `Label` (the current line's speaker), text `Label` (typewriter), `Choices` (`VBoxContainer`), hint line.
- **Typewriter**: 0.05 s per character, delta-driven off `_process` (never `Engine.time_scale`). The advance press (Space / Enter / the player's `interact`) skips to the full line; the next press steps to the next line; after the last line, the entry's choices build, or with no choices the entry finishes.
- **Choices**: one `Button` per choice, built when the last line finishes typing, emitting `choice_selected(index, choice)`. The box does not navigate: `StoryManager` shows the `goto` target entry or closes on `end`.
- **Input pause**: while open, the box consumes advance / interact / cancel in `_unhandled_input` and the Dim stops world clicks — the local player's input is paused, the game is not: `get_tree().paused` is never touched, because in co-op the pause would be everyone's. The polled-movement half (the player reads `Input.get_vector` every physics tick) is locked with the town NPC wiring (W6-B4), which is also what opens the box.
- **Per-player**: one box per local view, stamped with `local_peer`; entries are selected through `StoryManager.select_entry()` with the local player's `EvalContext`, so co-op players talking to the same NPC each see their own flags' lines.
- **Signals**: `choice_selected(choice_index, choice)`, `dialogue_finished(entry_id)`. `StoryManager.start_dialogue(dialogue_id, npc)` loads `data/dialogue/<id>.json`, selects the entry, opens the box, resolves choices, and applies `on_end.set_flags` when the entry finishes (`on_end.give` is run-economy's payout path, not wired in the mock-up).

### Acts and beats (locked, design doc section 11)

| Act | Biomes | Key flags set |
|---|---|---|
| 1 The Fall | 1 to 2 | `story.foreman_defeated` (Brann unlock, Abyss tree unlock), `story.miners_possessed`, `story.pit_calls` |
| 2 The Descent | 3 to 4 | `story.vulkar_journals` (lore set), `story.drowned_city_found`, `story.pit_has_done_this_before` |
| 3 The Heart | 5 to 6 | `story.pit_feeds_on_loss`, `story.keeper_offer`, one of `ending.seal`, `ending.keeper`, `ending.true` |

Act transitions set flags on biome boss kills (`boss_defeated` listener) and on returning to town, which changes every NPC's dialogue and the town visuals (`town`).

### Endings

At The Sinkhole phase 3 (`bosses` calls `StoryManager.final_choice(context)`):

1. **Seal the Pit**: sacrifice carried relics (they are removed from `RunPlayerState`), final duel, town saved. Flag `ending.seal`.
2. **Become the Keeper**: take the power, dark ending, `ending.keeper`, unlocks Deep Mode with the player's dark version as extra boss (`endgame`).
3. **True Ending**: available only if `secret.watcher_defeated` and all lore pages read (`lore_unlocked_count() == total`): free the miners, destroy the heart, `ending.true`.

Each ending is a dialogue sequence plus a short scripted scene (`scenes/dialogue/endings/`). Any ending unlocks Deep Mode. Credits after.

### NPCs (8, design doc section 11 table)

Mayor Hilde (main quests), Gruff (Blacksmith, old mine stories), Moss (Alchemist), Pip (Map Maker, braver with depth: lines keyed on `deepest_floor_min`), Sister Ash (Shrine Keeper, knows more), Old Tom (Tavern, secret boss hints keyed on flags), Vesper (random appearances, cursed items; dialogue here, shop in `run-economy`), The Rescued (each rescued miner has a small dialogue set in Rescue Camp). Each NPC has at least: intro, per-act lines, reaction to each town level of their building, reaction to each ending.

### Rescue missions

`RescueMission` data (`data/dialogue/rescues.json`): miner id, display name, biome, floor range, unlock (class id or camp bonus id), dialogue id. On a matching floor (host rolls 35% chance per eligible floor, guaranteed on the biome's floor 4 if not yet rescued), the generator places a `Cage` interactable in a non-combat room. Freeing spawns an `EscortNpc` (`enemies-ai`) that follows the freeing player. Reaching the next rope (floor 2 rope or boss rope) with the escort alive sets `rescue.<id>`, emits `miner_rescued`, unlocks the class or camp bonus, and the miner appears in town. Escort death: mission fails for this run, retry next run. Class miners: Sly Nettie (Rogue, Fungal Caverns), Cogsworth (Engineer, Crystal Hollows), Mortimer (Necromancer, Drowned City), Elian (Lightbearer, Ember Forge). Non-class miners (at least 4) give Rescue Camp passives (`town`).

### Character threads

3 personal events per character (12 total), triggered as dialogue in town or special rooms by `character` condition plus progress flags: Wren (father's helmet, Foreman's words, the heart's call), Brann (his brother the Foreman, armor he kept, choosing to stay still), Ivy (the 5 lanterns, the light at the bottom, Sister Ash), Kestrel (why she drifts, the dodge that saved her, staying). Written in week 10.

### Lore

40+ pages across biomes (at least 6 per biome plus Vulkar's journals). `LORE` room populator spawns a `LorePage` pickup for the lowest-order unread page of that biome. Codex view in `ui-hud` lists them by biome with read state. Collecting all is required for the true ending.

### Secret boss triggers (flags owned here, fights in `bosses`)

Rat King hidden wall (Biome 1, breakable marker), Golden Spore item + hidden room (Biome 2), Fishing Rod item + fishing spot (Biome 4), the town well eye after any ending (`ending.*` set). Old Tom hints at each.

## Interfaces provided

`StoryManager` API, `DialogueData`, `DialogueBox` (`show(dialogue_id, npc)`), `RescueMission`, `Cage`, `LorePage`, flag namespace rules, `final_choice(context) -> Ending`. Events: `story_flag_set`, `lore_unlocked`, `miner_rescued`.

## Interfaces consumed

- `save-system`: `story_flags`, `lore_unlocked`, `rescued_miners`, `endings_seen`.
- `run-economy`: rope reached event for escorts, `give` rewards.
- `enemies-ai`: `EscortNpc`.
- `floor-generation`: `LORE` populator, `Cage` placement hook.
- `town`: NPC nodes call `StoryManager.start_dialogue`.
- `bosses`: `boss_defeated`, `final_choice`.

## Data model

JSON under `data/dialogue/` and `data/lore/`, schema in `specs/content/dialogue-schema.md` (written week 6). Portraits under `assets/sprites/portraits/`.

## Multiplayer ownership

Flags are per player (progress is per player per design doc section 12) and set on the host for the acting player, then included in `run_summary`. Pit dialogue triggers (lore, rescue) broadcast to all; the triggering player makes choices. Town NPC dialogue is local to each player's view of the host's town using the local player's flags for conditions.

Sync: host sets flags, per-player merge at run end.

## Testing

- Data-driven `test_dialogue_data.gd`: every JSON parses, matches schema, references only declared flags, every `goto` resolves, every NPC has required entries (intro, acts 1 to 3, endings), 40+ lore pages with unique `order` per biome, 12 character events, 8 rescue missions with 4 class unlocks.
- Unit `test_story_conditions.gd`: every condition operator; priority selection; fallback.
- Unit `test_story_acts.gd`: act derivation from flags; ending availability rules (true ending gated on Watcher and lore count).
- Integration: rescue flow with a fake escort reaching a fake rope sets the flag and unlocks the class.
- Manual: read-through of all dialogue in week 10 by both devs for tone.

## Success criteria

- [ ] Week 6: dialogue system, Hilde/Gruff/Moss/Pip/Ash/Tom with intro and Act 1 lines, flags saved, Foreman kill changes town dialogue.
- [ ] Week 7: rescue missions with escort; Sly Nettie unlocks Rogue.
- [ ] Week 10: all NPC dialogue through all acts, 3 endings playable, 40+ lore pages, codex, 12 character events.
- [ ] Every flag referenced anywhere is declared; CI enforces.

## Open questions

- Portrait art for 8 NPCs + 4 characters + rescued miners: placeholder silhouettes until `art-audio` week 12.
