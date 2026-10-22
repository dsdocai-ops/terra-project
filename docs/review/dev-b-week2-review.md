# Dev B week 2 review: items still open

Source: the week 2 code review of the Surface lane (networking spawners, debug console, HUD v0, AudioManager, smoke step 3), re-checked against `main` on 2026-10-21 after `feat/ui-hud-pixel-art-pass` merged. Items the branch already fixed are listed at the end so nobody re-reports them. Owner for every open item is Dev B unless the line says it waits on Dev A.

Severity: **high** = wrong behaviour a player or a test will hit; **medium** = wrong under a condition the game reaches; **low** = debt or spec deviation with no visible effect yet.

## Open

| # | Sev | Where | Problem | Fix |
|---|---|---|---|---|
| 1 | high | `scripts/ui/hud_model.gd:234` `_read_hp` | Requires `current_hp` and `max_hp` to both be `int`; anything else returns the full-bar fallback with no warning. `StatBlock.get_value()` returns `float`, so a `Health` whose `max_hp` comes from `MAX_HP` as a float shows a full bar forever. `tests/helpers/fake_health.gd` hardcodes ints, so no test sees it. | Accept `int` or `float` (`is_finite` + `roundi`), warn once when a field is missing. Add a test with float HP. |
| 2 | high | `scenes/ui/hud.gd:186` `_on_weapon_swapped` | Discards the `player` argument and calls `set_weapon_active(slot)` for every peer's swap, so a teammate swapping moves the local player's active-slot highlight. | Return unless `player.is_local` (or the peer id matches `NetworkManager.local_peer_id`). Test: a remote swap leaves the active slot alone. |
| 3 | medium | `scripts/autoload/audio_manager.gd:165,178` | Both SFX pools are created on `BUS_SFX`; `BUS_UI` is declared and ensured but never assigned, so the UI volume slider has no effect on UI sounds. | Non-positional (`_plain_pool`) players on `BUS_UI` or pick the bus per id from `SfxBank`; test that a `ui_*` id plays on the UI bus. |
| 4 | medium | `scripts/autoload/audio_manager.gd:169,182` | Comment says "the oldest" is stolen when a pool is full; code returns `pool[0]` every time, so under load one player is cut over and over. | Keep a rotating index or steal the player with the smallest remaining playback time. |
| 5 | medium | `scripts/autoload/network_manager.gd:223` `request_debug` | Host and sender checks are in; still no host opt-in (a client can run console commands on any debug build the host did not open for it), no per-peer rate limit, no command-line length cap. | Gate on a host-side `debug_remote_enabled` flag (default off outside `--debug-tools`), cap length (256), drop more than N per second per peer, log the drop. |
| 6 | medium | `scripts/debug/debug_commands.gd:223` `_cmd_kill` | Reads `current_hp` on the entity root. The placeholder enemy keeps it there; the real enemy keeps HP on a `Health` child (SPEC-combat-core), so `int(null)` is 0 and nothing dies. | Look up `health` (child or property) first, fall back to the root field; test with a `Health`-child double. Waits on Dev A's `Health` for the real shape, but the fallback can land now. |
| 7 | medium | `scenes/ui/hud.gd:286` `_rebuild_teammates` | Every poll (`POLL_INTERVAL` 0.25 s) frees and recreates every teammate badge. Allocation churn for a list that changes on join/leave only; also loses any per-badge animation state. | Diff by `peer_id`: create, update in place, free on leave. |
| 8 | medium | `scenes/main/main.gd:263` `_maybe_add_hud` | No mode check: the HUD is added in menu mode too. | Add only when a run starts (`GameState` run signal) or guard on the launch mode; free it on return to menu. |
| 9 | low | `scripts/ui/hud_model.gd:70`, `scenes/ui/hud.gd:45` | Binds to `NetworkManager.players` for the roster; SPEC-ui-hud names `RunPlayerState` (via `GameState.run`) as the source. `refresh()` already reads `run.get_player()` for the local player, so the two sources can disagree for teammates. | Bind the roster to `GameState.run` players; keep `NetworkManager` for peer ids only. |
| 10 | low | `scripts/ui/hud_model.gd:30` `HudWeaponSlot.display_name` | Plain field, no setter and no change signal, so the weapons module (W2-A7) has to poke the array element and nothing re-renders until the next poll. | `set_weapon_slot(index, id, display_name)` on `HudModel` that updates and emits `changed`. |
| 11 | low | `scripts/debug/debug_console.gd:21` `_god_peers` | God-mode state lives in the console; `Health` must not reference the console (stripped from release). | Move god-mode to a host-side flag the console sets (`GameState` or the player), consumed by `Health` when it lands. |
| 12 | low | `tests/unit/test_hud_model.gd:56` | `test_local_hp_ratio_clamps_at_zero` feeds 0/100, which exercises no clamping. | Feed a negative `current_hp` and a `current_hp > max_hp` case. |
| 13 | low | `tests/unit/test_console_parser.gd:506` | `test_request_debug_runs_on_the_host_and_validates_sender` passes only because a local call has remote sender id 0; the refusal path for a spoofed peer id is not covered. | Drive the RPC through a double that reports a different `get_remote_sender_id()`, assert the warning and no emission. |
| 14 | low | `assets/audio/sfx/*.wav`, `data/audio/sfx_bank.tres` | Placeholder SFX are `.wav` from the Godot tool and the bank hardcodes `.wav` paths; the spec's pipeline is `.ogg` from `tools/audio/build_sfx.py`. Real files cannot replace them "without touching the bank". | Part of W2-B7 (`synth.py` + `build_sfx.py`): render `.ogg`, point the bank at `.ogg`, delete the `.wav`. |
| 15 | low | `CREDITS.md` line 3, `tests/integration/` | `CREDITS.md` says `tests/integration/test_credits.gd` checks the table; the test does not exist (only the Python `test_credits_table.py` does). | Add `test_credits.gd` per SPEC-art-audio "Testing" (every sourced file has a row with an allowed license, every row's path exists), or reword the preamble until it lands. W2-B7 names it. |

## Waits on Dev A

| # | Where | Problem | Who moves first |
|---|---|---|---|
| 16 | `scenes/player/player.tscn` StateSync | `is_downed` now replicates (property 5), but no `Health` fields do, so teammate HP bars stay on the fallback. | Dev A adds `Health.current_hp` / `max_hp` to StateSync in W2-A1; Dev B's #1 above must accept whatever type lands. |
| 17 | `scripts/components/hit_data.gd`, `scripts/autoload/events.gd` | `HitData` is the week-2 stand-in for `HitInfo`. Decision 2026-10-21: `HitInfo` replaces `HitData` (rename in the W2-A1 PR, every reference retyped, no adapter). Recorded in SPEC-combat-core and `tasks/todo.md`. | Dev A in W2-A1. |

## Fixed on the merged branch (no action)

- `audio_manager.gd` `_stopping` is cleared on instant stop and when a stop fade completes, so a track started during a fade is no longer silenced.
- `request_debug` refuses on non-hosts and validates the claimed peer id against the real sender.
- The UI font comes from `tools/art/gen_font.py` (own work, generated, no credits row needed); the out-of-tree placeholder font generator is gone.
- `tests/unit/test_hud_model.gd` has a real missing-`Health` case (`_make_player(..., false, false)`).
- `scripts/data/sfx_bank.gd` and the other `scripts/data/` additions are logged in `docs/review/questions.md` with a reason, which is the project's ask-first record.
- `timeslow` is covered by `test_timeslow_slows_enemies`.
