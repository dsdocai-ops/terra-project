# W5-B2 Plan: Rope Voting and Death/Extract Currency Rules

## Overview
Implement rope extraction voting for co-op (unanimous living players, downed excluded, `no` cancels) and death/extract currency rules table. Vote state is host-owned and broadcast by GameState. Tests and smoke step 3 validate all functionality.

## Goals

- [x] G1: Vote state tracking and request_extract_vote logic
  - **Why it matters**: Vote tallying is the core synchronization point for extraction in co-op. Solo extracts immediately; co-op waits for unanimous yes from all living players.
  - **Success criteria**:
    - RunState tracks per-player vote state (_vote_yes dict or similar)
    - GameState.request_extract_vote(peer_id, yes) tallies votes
    - Solo extraction (1 player) calls end_run(EXTRACT) immediately
    - Co-op: first yes is recorded, subsequent yes votes tally, any no vote cancels and resets
    - Downed and dead players are excluded from tallies
    - rope_vote_updated signal broadcasts vote state when changed
    - Vote state clears when rope_deferred.emit() or when re-entering the rope (fresh vote call)
  - Sub-tasks:
    1. Add _vote_yes: Dictionary[int, bool] and _vote_tally: int to RunState
    2. Add reset_vote_state() method to RunState for rope re-entry
    3. Implement request_extract_vote() in GameState with solo check
    4. Count "living" players (not is_downed and not is_dead) for unanimous logic
    5. Implement no-vote cancellation with reset
    6. Add rope_vote_updated signal to Events (or GameState)
    7. Broadcast vote state on any change

- [ ] G2: Unit test test_vote.gd covering all voting scenarios
  - **Why it matters**: Vote logic must be exhaustively tested before it reaches the smoke test. Each scenario (solo, co-op unanimous, downed excluded, no cancels, repeated use) is a separate invariant.
  - **Success criteria**:
    - `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=test_vote.gd -gexit` returns exit code 0
    - Solo vote (1 player) extracts immediately
    - Co-op 2 yes votes extract (both players vote yes)
    - Co-op 1 yes 1 no cancels (no vote resets tally)
    - Co-op 1 yes 1 downed extracts (downed not counted in tally)
    - All downed (no living) refuses to extract (run already in DEFEAT)
    - Repeated rope use after cancellation starts fresh vote tally
    - No new test failures or count changes
  - Sub-tasks:
    1. Create tests/unit/test_vote.gd with GutTest base
    2. Build RunState/RunPlayerState fixtures with controlled downed/dead states
    3. Write test_solo_immediate_extract
    4. Write test_co_op_two_yes_extracts
    5. Write test_co_op_one_no_cancels
    6. Write test_co_op_downed_excluded
    7. Write test_all_downed_refuses
    8. Write test_fresh_vote_after_cancellation

- [ ] G3: Populate RunResult kept/lost tables with death/extract currency rules
  - **Why it matters**: Currency handling at run end is the economic foundation. Each of the 5 currencies has different keep/loss rules for extract vs death, plus relic modifiers (Deep Pockets, Ore Heart, Safe Line) that change the outcome.
  - **Success criteria**:
    - GameState.end_run() computes kept/lost tables for each peer using SPEC-run-economy table
    - Extract: gold 100%, ore 100%, echo shards kept, class XP kept, relics lost (Safe Line keeps 1 random)
    - Death: gold 25% + Deep Pockets (10%/rank), ore lost (Ore Heart keeps 50%), echo shards kept, class XP kept, relics lost
    - Co-op shared gold split evenly: shared_gold / party_size (integer division)
    - Co-op shared ore split evenly: each ore_id amount divided by party_size
    - Co-op death rule: apply death rules once to shared pools, then split
    - Co-op extract rule: split shared pools first, then apply extract rules
    - Relics list in kept/lost identifies which relics by id
    - No UI changes, no save schema changes
  - Sub-tasks:
    1. Sketch currency rule logic in end_run() with comments (pseudo-code)
    2. Implement gold rule: 100% on extract, 25% + Deep Pockets on death
    3. Implement ore rule: 100% on extract, 0% + Ore Heart (50% capstone) on death
    4. Implement relic rule: lost on both, Safe Line node keeps 1 random
    5. Echo shards and class XP: always kept on both extract and death
    6. Implement co-op split logic: shared currency division by party_size
    7. Implement co-op death rule: apply to shared pools first, then split
    8. Populate RunResult.kept[peer_id] and RunResult.lost[peer_id] for each peer

- [ ] G4: Unit test test_death_rules.gd covering all currency rows with and without relics
  - **Why it matters**: Currency rules are the game's economic contract. Every combination of currency, run end reason, and relic modifier must be verified.
  - **Success criteria**:
    - `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=test_death_rules.gd -gexit` returns exit code 0
    - Extract with no relics: gold 100%, ore 100%, relics lost, echo/class_xp kept
    - Death with no relics: gold 25%, ore 0%, relics lost, echo/class_xp kept
    - Deep Pockets rank 1 on death: gold 25% + 10% = 35%
    - Ore Heart (capstone) on death: ore 50% kept
    - Safe Line on extract: 1 random relic kept out of lost set
    - Co-op 2 players extract: shared_gold / 2, shared_ore / 2
    - Co-op 2 players death: apply death rule to shared pools, split result
    - All currencies in all combinations: gold, ore, echo_shards, class_xp, relics
    - No new test failures or count changes
  - Sub-tasks:
    1. Create tests/unit/test_death_rules.gd with GutTest base
    2. Build RunState/RunPlayerState fixtures with gold, ore, echo shards, class XP
    3. Build relic inventory fixtures (Deep Pockets, Ore Heart, Safe Line)
    4. Write test_extract_keeps_gold_ore_100_percent
    5. Write test_death_keeps_gold_25_percent
    6. Write test_death_loses_all_ore
    7. Write test_deep_pockets_adds_10_percent_per_rank
    8. Write test_ore_heart_keeps_50_percent
    9. Write test_safe_line_keeps_one_random_relic
    10. Write test_echo_shards_always_kept
    11. Write test_class_xp_always_kept
    12. Write test_co_op_extract_splits_shared_currencies
    13. Write test_co_op_death_applies_rule_then_splits

## Notes

- Vote state must reset when the rope is interacted with again (fresh vote call). Tracked as _vote_tally or dict per peer.
- Downed and dead players excluded from unanimous count: count = sum of (1 for each peer if not is_downed and not is_dead).
- Co-op split: integer division (GDScript's / operator), so a 3-gold split among 2 players is 1 + 1 (one gold lost).
- Relic modifiers (Deep Pockets, Ore Heart, Safe Line) are checked by id in the player's relics list, not flags on run state.
- SafeLine keeps 1 random relic from the lost set, not earned in run; the table says "lost (run only)", so Safe Line modifies the rule.
- No new Events signals needed; rope_vote_updated can be added to GameState if needed, or broadcast via Events.
- Smoke test step 3 checks enemy sync; vote logic does not touch enemy spawn/kill, so existing checks should pass.
