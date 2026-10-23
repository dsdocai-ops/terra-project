# Dialogue JSON schema

Canonical contract for `data/dialogue/*.json` (story-dialogue, week 6). The
loader (`scripts/data/dialogue_data.gd`, `DialogueData`) validates every rule
below; the data-driven test (`tests/integration/test_dialogue_data.gd`) fails
the suite on any violation, so bad content can never reach the game.

## File layout

One JSON object per file. File name must equal `id` (snake_case), e.g.
`data/dialogue/mayor_hilde.json` → `"id": "mayor_hilde"`. `flags.json` lives
in the same folder but is the flag declaration, not a dialogue file.

```json
{
  "id": "mayor_hilde",
  "portrait": "res://assets/portraits/hilde.png",
  "entries": [ ... ]
}
```

| Key | Required | Rules |
|---|---|---|
| `id` | yes | non-empty string, equals file name |
| `portrait` | no | `res://` path; file must exist; "" / absent = none |
| `entries` | yes | non-empty array, ≤ 64 entries, no duplicate ids |
| (unknown top-level keys) | — | rejected |

## Entries

```json
{
  "id": "intro",
  "priority": 10,
  "conditions": {"all": [{"flag_not": "story.met_hilde"}]},
  "lines": [ ... ],
  "choices": [ ... ],
  "on_end": {"set_flags": ["story.met_hilde"], "give": {"gold": 50}}
}
```

| Key | Required | Rules |
|---|---|---|
| `id` | yes | non-empty string, unique within the file; goto target |
| `priority` | yes | integer 0..100; higher wins the selection scan; ties break to file order |
| `conditions` | no | condition expression (below); absent/`{}` = always eligible |
| `lines` | yes | non-empty array of line objects |
| `choices` | no | array of choice objects |
| `on_end` | no | actions applied when the entry finishes |
| (unknown entry keys) | — | rejected |

Entry selection (runtime): scan entries in descending priority, first one
whose conditions pass wins. `DialogueData.entries_by_priority()` provides the
order; `entries_for_act(act)` pre-filters on a top-level `act_min`.

## Lines

`{"speaker": "Mayor Hilde", "text": "...", "emotion": "worried", "character_only": "wren"}`

- `speaker`, `text`: required, non-empty strings.
- `text`: ≤ 400 characters.
- `emotion`, `character_only`: optional strings (`character_only` = only show
  this line to the named playable character).
- Unknown keys rejected.

## Choices

`{"text": "I'm going in.", "goto": "intro_more", "set_flags": ["..."], "end": true}`

- `text`: required, non-empty, ≤ 80 characters.
- Exactly one destination: `goto` (string naming another entry in the same
  file — every goto is resolved at load time) **or** `end: true`. Both, or
  neither, is an error.
- `set_flags`: optional array of flag names, each must be declared in
  `flags.json`.
- Unknown keys rejected.

## on_end

`{"set_flags": ["story.met_hilde"], "give": {"gold": 50}}`

- `set_flags`: optional array of declared flag names.
- `give`: optional object; keys limited to `gold`, `ore`, `echo_shards`;
  values integers.
- Unknown keys rejected.

## Condition language

Expressions are objects; an empty object passes. Composites nest (depth cap 8):

| Op | Shape | Meaning |
|---|---|---|
| `all` | `{"all": [expr, ...]}` | every sub-expression true (empty array = true) |
| `any` | `{"any": [expr, ...]}` | at least one true (empty array = false) |
| `not` | `{"not": expr}` or `{"not": [expr]}` | exactly one sub-expression, negated |

Leaf operators (structural rules here; semantics live in
`StoryManager.evaluate()`):

| Op | Value type | Rules |
|---|---|---|
| `flag` | string | declared flag name |
| `flag_not` | string | declared flag name |
| `character` | string | non-empty character id |
| `class` | string | non-empty class id |
| `town_level` | object | `{building: string, min: int}` |
| `ore_min` | object | `{ore: string, min: int}` |
| `deepest_floor_min` | int | 1..30 |
| `rescued` | string | miner id |
| `act_min` | int | 1..3 |
| `random_chance` | number | 0..1 |

Unknown operators rejected. Every flag named anywhere (conditions,
`set_flags`) must be declared in `flags.json`.

## Flags

`data/dialogue/flags.json` declares every reserved flag name grouped by
namespace (`story`, `rescue`, `char`, `ending`, `lore`, `town`, `secret`,
`boss`). `"persist": true` marks a UNLOCK_FLAGS flag (written to the profile
immediately by `StoryManager.set_flag`); the test asserts the persist list and
`StoryManager.UNLOCK_FLAGS` never drift apart.

## Error reporting

`DialogueData.load_file(name, declared_flags)` returns a `LoadResult`:
`ok()` on success, else `errors` — one human-readable `"<file>: <what>"` line
per violation, all violations collected in a single pass (parse, schema,
gotop resolution, portrait existence). `load_all()` scans the whole folder
(skipping `flags.json`) for the data-driven test and startup.
