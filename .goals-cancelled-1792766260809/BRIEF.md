# W5-B2: Rope Voting and Death/Extract Currency Rules

## Objective

Implement rope extraction voting for co-op (unanimous living players, downed excluded, `no` cancels) and death/extract currency rules table. Solo extracts immediately. Vote state is host-owned and broadcast by GameState. Integrate with existing transport layer (Rope.interact and NetworkManager.request_vote_rope remain untouched).

## Definition of Done (checkable by running commands)

1. Unit test suite passes:
   ```powershell
   godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=test_vote.gd -gtest=test_death_rules.gd -gexit
   ```
   Exit code 0 required.

2. Headless two-instance smoke test step 3 remains green:
   ```powershell
   tools/smoke_two.sh
   ```
   No new FAIL lines appear.

3. Test file requirements:
   - `tests/unit/test_vote.gd`: covers unanimous living, downed excluded, `no` cancels, solo immediate
   - `tests/unit/test_death_rules.gd`: covers every currency (gold, ore, echo, class_xp, story/codex/achievements) for both extract and death modes, with relics lost on extract/kept on death

4. No test count changes: running `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` must produce the same total test count as main before this work started.

## In Scope

- Vote tallying state machine in `scripts/run/run_state.gd` (vote tracking per player during rope interaction)
- Vote broadcast and tally logic in `scripts/autoload/game_state.gd` (`request_extract_vote` implementation)
- Death/extract currency rules in `scripts/run/` (new files or embedded in GameState)
- RunPlayerState field(s) to track vote per player (extend existing structure)
- RunResult kept/lost table population with per-currency rules from SPEC-run-economy table
- Test fixture code for vote logic and currency rules
- Git commit(s) to feat/run-economy-W5-votes-deaths branch

## Out of Scope

- Vote prompt UI (week 5 scope but not this task; the votes themselves are pure logic)
- Save schema changes (use existing RunPlayerState fields)
- Changes to `Rope.interact` or `NetworkManager.request_vote_rope` (they handle transport; this task tallies votes sent through them)
- `scripts/autoload/events.gd` signal changes (vote signal if needed reuses existing patterns)
- Tests in other files (test_rope.gd, test_game_state_run.gd, etc. must pass unchanged)

## Constraints

### Stack and Files

- **Language**: GDScript 4.7.2 with strict static typing (no `untyped_declaration`).
- **Modules**: `run-economy` owner is Dev B; code goes in `scripts/run/` and `scripts/autoload/game_state.gd`.
- **Classes**: GameState (autoload), RunState, RunPlayerState, RunResult, RunEndReason (existing), plus new vote state struct if helpful.
- **Spec references**: SPEC-run-economy sections "Rope points", "Death and extraction rules", "Testing"; SINKHOLE_SPEC section 3 (rope points every 2 floors).
- **Test framework**: GUT (gut_cmdln.gd headless).

### Testing

- **Voting tests**: Test each row of voting logic (solo immediate, co-op unanimous, downed excluded, no cancels).
  - Test cases: 1 player votes yes (immediate extract), 2 players 2 yes (extract), 2 players 1 yes 1 no (cancel), 2 players 1 yes 1 downed (extract after living voting yes), all downed (run already in DEFEAT state).
  - Solo and co-op paths differ; both must work.
- **Death rules tests**: Test each row of the SPEC-run-economy table (gold, ore, relics, echo shards, class XP) for both extract and death with and without relevant relics (Deep Pockets, Ore Heart, Safe Line).
  - Co-op split math: shared pools split evenly among party on extraction; on death the party's shared pools suffer the death rule once then split.
  - Relics lost on extract, kept on death.
- **No new GUT issues**: Running full test suite must still pass (no test-ordering bugs, no new contamination).

### Style

- Ownership comment in each stateful script: "Owned by run-economy (week 5)."
- Host-only methods guarded: `if not NetworkManager.is_host: return`
- Vote state fields prefixed `_vote_*` to keep vote tracking separate from earnings tracking.
- No comments on WHAT the code does (the code says that); comments only on WHY (hidden constraints, non-obvious invariants).

## Assumptions

1. **Solo extraction is immediate**: Rope.interact() on a solo run calls `request_extract_vote(peer_id, yes)` immediately without prompting; GameState ends the run with EXTRACT reason without tallying.
2. **Co-op extraction requires unanimous yes**: All non-downed, non-dead players must call `request_extract_vote(peer_id, yes)`. The first peer to vote yes is recorded; subsequent yes votes are tallied; any no vote cancels.
3. **Downed and dead players don't vote**: RunPlayerState.is_downed and RunPlayerState.is_dead exclude that player from the tally. Vote state must track "living" as `not is_downed and not is_dead`.
4. **Vote is broadcast, not per-peer**: When a vote is tallied, a `rope_vote_updated` signal (or similar) broadcasts to all peers so the UI knows the current vote state (even though UI is not built this week).
5. **No vote cancellation persists**: A `no` vote cancels the rope and resets all vote counters. The rope becomes usable again (Rope.interact() can be called again).
6. **Vote tracking is per rope call**: Calling Rope.interact() again starts a fresh vote tally; prior vote state is cleared.
7. **Death/extract rules use the exact table**: SPEC-run-economy "Death and extraction rules" table is the source of truth. No relics recovered on extract (Safe Line node is a relic that breaks this rule, kept separate). Ore lost on death (Ore Heart capstone keeps 50%, kept separate).
8. **RunResult.kept and RunResult.lost are populated by end_run()**: Currently neutral; week 5 computes currency-by-currency based on RunEndReason and relic inventory.
9. **Relics are a list in RunResult.lost, not a count**: The table says relics "lost (run only); Safe Line node keeps 1 random". Relics list in kept/lost table identifies which ones; Safe Line is a relic that modifies the rule.
10. **No network RPC changes**: Rope.interact() and NetworkManager.request_vote_rope() exist; this task does not modify them. They send the vote to the host; GameState receives and tallies.
11. **No save-system integration this week**: RunResult is not saved to disk (that's week 5 banking); it is built and broadcast on `run_ended`, then discarded.
12. **Coins and currencies are per the table, not per relic**: Gold, ore, echo shards, class XP follow the table exactly. Relics (Deep Pockets, Ore Heart, Safe Line) modify the rule by being in the inventory; they are not stored as flags on the run state.
13. **Co-op shared pools split evenly**: `shared_gold / party_size` (integer division) is each player's share. Shared ore is a dictionary (ore_id -> amount); split the amount, not the entry.
14. **Echo Shards and Class XP are always kept**: Death and extract both keep these; the table confirms it.

## Removed from the Request

Nothing removed. The request is a precise spec suitable for unattended work. The "no UI" constraint is respected by not adding UI code; tests replace user visibility. Progress logging via .goals/LOG.md replaces interactive updates.

