# Progress Log

G1 (step 1): added rope vote state to RunState (`_vote_yes: Dictionary[int, bool]`, `_vote_tally` getter, `record_yes_vote()`, `has_open_vote()`, `has_voted_yes()`, `vote_state()`, `reset_vote_state()`) and implemented host-only `GameState.request_extract_vote(peer_id, yes)` in `scripts/autoload/game_state.gd` — solo run ends immediately with EXTRACT, co-op records yes votes and ends when every living player (not `is_downed`, not `is_dead`) has voted yes, a `no` cancels and resets, a repeat yes from a peer whose vote is already recorded starts a fresh call (BRIEF Assumption 6), and every change broadcasts `Events.rope_vote_updated(votes)`. rope.gd and NetworkManager left untouched (transport only).

G1 verification: full headless GUT suite passes 1235/1235 (same script/test counts as main — only the two script files changed, no test files touched); `tools/smoke_two.sh` runs green with zero FAIL lines (steps 1, 2, 3 and floor sync all ok). No plan goals ticked; test_vote.gd/test_death_rules.gd belong to G2/G4 (later steps).
- G1: Vote state tracking and request_extract_vote logic: passed the judge (Claude account), step 1.
