# Weekly build notes

One entry per week, written before tagging `week-N`. Template below. Required by [SPEC-project.md](SPEC-project.md#testing-strategy).

## Template

```
## Week N (YYYY-MM-DD)  tag: week-N

Done when (design doc section 20): <copy the line>
Met: yes / partial (what is missing)

Checklist
- [ ] CI green on main
- [ ] Two-machine co-op session (who, duration, latency used)
- [ ] Perf scene FPS min/avg, machine A / machine B (from week 4)
- [ ] Classes and Ascensions tested solo and co-op this week: ...
- [ ] Time effects tested in co-op (from week 4)
- [ ] New relics/mutations/abilities trigger-tested and co-op checked: counts
- [ ] External playtest notes (from week 9)
- [ ] Every [art-audio] task this week has an approved review sheet in docs/asset-review/week-N/ (or a dated polish-list entry)

Decisions and spec updates
- ...

Cut list actions (should be empty)
- none

Next week risks
- ...
```

## Entries

## Week 1 (2026-10-18)  tag: week-1

Done when (design doc section 20): Isometric TileSet, Y-sort, player movement, camera. 2 players can connect and see each other move (host + client)
Met: yes — verified headless on one machine (import exit 0; 18 GUT scripts / 204 tests green in ~7 s; two-instance smoke 15/15 ok). The visual pass (crisp pixels, movement feel, camera zoom) is manual and on Dev A's machine; it is listed below as a non-blocking checklist.

Checklist
- [ ] CI green on main — workflow triggers on `push` to `main` (no PR flow in use); the same import + GUT jobs are green locally. Live Actions run not observable from this machine (no `gh`/token) — outstanding, non-blocking.
- [ ] Two-machine co-op session (who, duration, latency used) — not run; only this machine was available. Dev A on their machine is outstanding, non-blocking (one-machine two-instance smoke is green).
- [ ] Perf scene FPS min/avg, machine A / machine B — N/A (perf scene is week 4).
- [ ] Classes and Ascensions tested solo and co-op this week — N/A (classes are week 5).
- [ ] Time effects tested in co-op — N/A (TimeManager is week 2).
- [ ] New relics/mutations/abilities trigger-tested and co-op checked — N/A (week 4+).
- [ ] External playtest notes — N/A (week 9).
- [x] Headless two-instance smoke steps 1 and 2 (`tools/smoke_two.sh`): 15/15 ok, exit 0, ~11 s.
- [x] `week-1` tag created and pushed to `origin`.

Decisions and spec updates
- Every unapproved week-1 decision is recorded in `HANDOFF.md` (14 items), including `physics_interpolation = true` (not in the SPEC-foundation table), `inferred_declaration` left at Ignore, the controller-binding deviation (ability_2 RB / ability_3 R3 / ultimate L3, no chords), the added `--smoke` launch arg, solo-as-host-with-one-peer, and the `World/Players` Y-sort flag.
- GUT 9.7.1 (tag `v9.7.1`) vendored under `addons/gut/`; recorded in `SPEC-foundation.md` open questions.
- CI downloads the official `Godot_v4.7.2-stable_linux.x86_64` build from `godotengine/godot-builds` (no third-party setup action); recorded in `SPEC-foundation.md` open questions.
- Week-1 smoke steps 1 and 2 pass on this machine; the "both developers ran the smoke on their own machine" item from W1-AB2 remains outstanding for Dev A (non-blocking).

Cut list actions (should be empty)
- none

Next week risks
- Dev A's week-2 assets (`enemy_base.tscn`, `Projectile`, `Health`, `HitInfo`) have not landed; W2-B3 (enemy/projectile spawners + StateSync) and W2-B5 (HUD) build against spec interfaces and `tests/helpers/` stubs and record each as "blocked on Dev A (W2-Ax)".
- CI live-run observability is limited on this machine (no `gh`/token); the green/red behavior is proven locally and the workflow config is reviewed.
- Manual feel checks (viewport scaling, controller icons, 3-instance run) are non-blocking and listed in `HANDOFF.md`.

## Week 2 (2026-10-19)  tag: week-2 (not created — see Met)

Done when (design doc section 20): Light/heavy attacks, dodge, weapon swap, Health/Hitbox/Hurtbox components, 3 enemies with telegraphs, all synced in co-op
Met: partial — Dev B's Week 2 lane is complete: TimeManager (W2-B1), StatBlock + Damage.compute + golden file (W2-B2), enemy/projectile spawners with StateSync and host-only hit resolution (W2-B3), debug console + `request_debug` (W2-B4), HUD v0 + HudModel + Theme (W2-B5), AudioManager + SfxBank (W2-B6), and the two-instance smoke now covers all three steps (28/28 ok — step 3 drives the W2-B3 enemy stub end to end: client spawns/attacks a stub enemy, HP drops on both screens, kill registers once). Dev A's W2 tasks (W2-A1..A13, the "Done when" combat core: attacks, dodge, weapon swap, Health/Hitbox/Hurtbox, 3 enemies) have NOT landed, so the design-doc "Done when" is unmet and `week-2` is left untagged (BRIEF Assumption 10) until the checkpoint passes in full. Verified headless on this machine: import exit 0 with no errors; 27 GUT scripts / 338 tests green (~14 s).

Checklist
- [ ] CI green on main — workflow triggers on `push` to `main`; the same import + GUT jobs are green locally. Live Actions run not observable from this machine (no `gh`/token) — outstanding, non-blocking (same as week 1).
- [ ] Two-machine co-op session (who, duration, latency used) — not run; only this machine was available. One-machine two-instance smoke is green (below); Dev A's machine session is outstanding, non-blocking.
- [ ] Perf scene FPS min/avg, machine A / machine B — N/A (perf scene is week 4).
- [ ] Classes and Ascensions tested solo and co-op this week — N/A (classes are week 5).
- [ ] Time effects tested in co-op — covered by W2-B1 in GUT + the co-op smoke harness (timestop/timeslow commands run on the host in a two-instance session; recorded in HANDOFF manual checks). Devil's-clock co-op visual not manually played — non-blocking.
- [ ] New relics/mutations/abilities trigger-tested and co-op checked — N/A (week 4+).
- [ ] External playtest notes — N/A (week 9).
- [ ] Every W2 `[art-audio]` task has an approved review sheet in `docs/asset-review/week-2/` — the asset-pipeline tasks (W2-A11/A12/A13, W2-B7/B8) are not done; placeholder pipeline recorded in decisions below. Outstanding, tracked in `tasks/todo.md`.
- [x] Headless two-instance smoke steps 1 to 3 (`tools/smoke_two.sh`): 28/28 ok, exit 0 (~35 s).
- [x] Week-2 feel-pass checklist recorded (manual, non-blocking) — see Feel pass below.
- [ ] `week-2` tag — NOT created. The full Week 2 checkpoint includes Dev A's tasks (W2-A1..A13), none of which have landed; per BRIEF Assumption 10 the tag waits for the complete checkpoint. State recorded here and in `.goals/LOG.md`.

Feel pass (manual, non-blocking — headless on one machine cannot judge these; Dev A + human verify in a windowed run)
- [ ] Time effects — `timestop 2` / `timeslow 2` from the debug console feel responsive (hit-stop on parry/attack not yet in the game — needs combat core).
- [ ] HUD legibility — own HP bar, teammate bars, weapon slots, floor label read cleanly at 1920x1080 with the placeholder pixel font; weapons not yet present so slots show the empty frame (W2-B5).
- [ ] Enemy stub feel — spawn `spawn grub 3` and watch 3 stubs pace; HP 10 drops to 7 on both screens when the host resolves a hit; `kill` clears them and the game doesn't hitch (W2-B3).
- [ ] Audio feel — placeholder clicks on proxied actions; music crossfade plays when the first tracks land (W2-B6/A13).
- [ ] Console UX — backtick opens/closes on a windowed run; `help` lists commands; client-side `gold 50` grants to that peer (W2-B4; logic covered headless).

Decisions and spec updates
- Smoke step 3 ships against the W2-B3 placeholder enemy (`scenes/network/placeholder_enemy.gd`, HP 10, no AI) because Dev A's `enemy_base.tscn` (W2-A9) has not landed. The step is specified in `SPEC-networking.md`; swapping in the real enemy is data-only: `EnemySpawner.enemy_scene` points at Dev A's scene once it keeps the replicated-prop names `synced_position` / `current_anim` / `current_hp`. The `kill` command routes through `request_debug` + the host DebugConsole, so step 3 also exercises the whole debug-tools round trip.
- New `--smoke3=<sec>` launch arg (LaunchArgs) mirrors `--smoke`; `tools/smoke_two.sh` runs steps 1+2, then a second host/client pair for step 3 on the same port after a socket-release beat. The host resolves the partial hit only after the client has joined and the enemy has sat at full HP for ~1 s, so the HP drop is observed on both screens before the kill.
- No base stats, `Engine.time_scale`, Dev A `.tscn`, or project.godot changes in this week; all W2-B decisions are recorded per-task in `.goals/LOG.md` and in `HANDOFF.md` decisions 15–21 (handles API, golden table, host-only refusal paths, lazy HUD/console loading, runtime audio buses).

Cut list actions (should be empty)
- none — placeholder-backed stubs (enemy, projectile, SFX, font) are tracked swaps, not cuts; each is recorded as blocked on Dev A or as a placeholder-first pipeline decision.

Next week risks
- Dev A's week-3 floor generation depends on the combat core (W2-A1..A13) still being open; if it doesn't land early in week 3, floor-gen (Dev A) and its consumers (locked-room downed/revive states — Dev B systems) both slip.
- Placeholder enemy has no telegraphs/attacks; co-op combat testing of TimeManager hit-stop and HUD teammate damage waits on W2-A10's enemies.
- The `week-2` tag is off; if Dev A's tasks land mid-week-3 the team should tag retroactively before building on the combat core, or explicitly re-scope the milestone with a human.

## Week 3 (2026-10-20)  tag: week-3 (not created — see Met)

Done when (design doc section 20): Procedural floors with Start, Combat, Elite Combat, Treasure, Rope, Exit rooms, locking combat rooms, seed sync for co-op, downed/revive
Met: partial — Dev B's Week 3 lane is complete (W3-B1 to W3-B5, all sub-tasks ticked with evidence in `tasks/todo.md`), but the design-doc "Done when" line is **unmet** and `week-3` is **left untagged** (decision 37 below, following the decision-22 precedent for `week-2`). Missing, and all of it Dev A's lane: **W3-A1** `FloorGenerator.generate()` (no `scripts/generation/floor_generator.gd` exists — the folder holds only `.gdkeep`, so every floor the game generates today comes from the lane-B `FloorLayoutPlaceholder` through `FloorGeneratorSeam`), **W3-A2** the `Floor` scene with room types, door locking and the Exit rule (so there are no Start / Combat / Elite Combat / Treasure / Rope / Exit rooms and no locking combat rooms), **W3-A3** the populator registry and the real 500-seed soak over the generator (the lane-B soak shipped instead — see below), **W3-A4** `SpawnDirector` v1, **W3-A5** the `Downed`/`Dead` states that actually down a player, **W3-A6** the Biome 1 tileset and room markers, and **W3-A7** the downed/death/rope SFX. Of the "Done when" line's eight clauses, **seed sync for co-op is met** and **downed/revive is met on Dev B's half only** (the replicated flag, both broadcasts and the host revive rule ship and are tested; nothing in a launched game can down a player yet). Verified on this machine at `84395b4` (logs in `.goals/evidence/g6/`): `--import` exit 0 with 0 error lines; full GUT **35 scripts / 554 tests / 554 passing / 54 115 asserts, exit 0** in 9.8 s; `tools/smoke_two.sh` **35 `ok` lines / 0 FAIL / exit 0**.

Checklist
- [ ] CI green on main — workflow triggers on `push` to `main` (no PR flow in use); the same import + GUT jobs are green locally, and the 500-seed soak that the checkpoint asks CI to run is part of the suite. Live Actions run not observable from this machine (no `gh`/token) — outstanding and non-blocking, the same item as weeks 1 and 2.
- [ ] Two-machine co-op session (who, duration, latency used) — not run; only this machine was available. The one-machine two-instance smoke is green (below) and a two-machine session remains outstanding, non-blocking.
- [ ] Perf scene FPS min/avg, machine A / machine B — N/A (perf scene is week 4).
- [ ] Classes and Ascensions tested solo and co-op this week — N/A (classes are week 5).
- [ ] Time effects tested in co-op — TimeManager's group/per-entity scaling and its `time_effect_applied` / `entity_time_applied` broadcasts stand from week 2 (`tests/unit/test_time_manager.gd`, `tests/integration/test_time_scale_movement.gd`); the `timestop` console command was **not** re-run across two instances this week. Its co-op verification is week 4's W4-B9 — recorded rather than claimed.
- [ ] New relics/mutations/abilities trigger-tested and co-op checked — N/A (week 4+).
- [ ] External playtest notes — N/A (week 9).
- [ ] Every W3 `[art-audio]` task has an approved review sheet in `docs/asset-review/week-3/` — **not met**: W3-B6 (rope vote prompt, floor label pieces, downed/revive HUD icons, death/extract summary theme, and the rope/revive/downed/menu SFX) is open, and W3-A6/A7 have not landed. The spec's placeholder rule is in force (a coloured square with the first letter; the HUD uses the generated 5×7 placeholder font). W3-B6 is an art-audio task, is not in this run's task list, and is carried as an open id with a dated deferral in `tasks/todo.md`.
- [x] Headless two-instance smoke steps 1 to 3 plus the floor-sync phase (`tools/smoke_two.sh`): **35 `ok` lines, 0 FAIL, exit 0** (`20261020` → `layout_hash 3600649381522393848`, `987654321` → `536024383148136417`, host and client equal on each seed).
- [x] 500-seed ceiling soak green (locally) — `tests/integration/test_floor_generation_seeds.gd`, 8 tests / 41 069 asserts / 1.9 s, over the lane-B `FloorLayoutPlaceholder` that `FloorGeneratorSeam` hands every peer today. The spec's own soak over `FloorGenerator.generate()` (flood-fill reachability, Exit reachable, exactly one `ROPE` on floor 2, no overlaps, 3-wide corridors) is **blocked on Dev A (W3-A3)**, and the soak's last case asserts the seam's source so it cannot silently keep covering the placeholder once the real generator lands.
- [ ] `week-3` tag — **NOT created.** The design-doc "Done when" line is partial (W3-A1 to W3-A7 unlanded; procedural floors and room types do not exist), and a milestone tag claims the whole line, not one lane's task list — the precedent set for `week-2` at decision 22. The gap is stated here, in `HANDOFF.md` decision 37, and in `.goals/LOG.md`.
- [x] `tasks/todo.md` — W3-B1, W3-B2, W3-B3, W3-B4 and W3-B5 are each ticked with their acceptance evidence and blocker annotations; the Week 3 checkpoint block carries the per-item state.

Decisions and spec updates
- Week 3's judgment calls are `HANDOFF.md` decisions **22 to 37** (starting with the recorded week-2 gate verdict at 22 and ending with this checkpoint's verdict and withheld tag at 37); the per-task reasoning is also in `.goals/LOG.md`.
- Every cross-lane dependency that did not land is recorded as `blocked on Dev A (W3-Ax)` in the file that needs it and in `tasks/todo.md`, and each swap-in is mechanical: the floor generator (`FloorGeneratorSeam` resolves `res://scripts/generation/floor_generator.gd` the moment it exists), the biome resource (`GameState.biome_for_index()` still returns a `BiomePlaceholder`), the Exit rule (`RunState.required_rooms_cleared` keeps its `0` default, meaning "no requirement declared yet"), the populator registry (`Rope.register_populator()` is a guarded no-op), and the down/revive states (the host already listens to the spec's `player_downed` / `player_revived` / `player_died`, so nothing on Dev B's side changes when they land).
- `NetworkManager` grew the floor-sync transport (`floor_ready`, `layout_asserted`, `floor_layout`), the player-state broadcasts (`broadcast_player_downed` / `broadcast_player_revived`), the request paths (`request_vote_rope`, `request_revive`, `request_floor_layout`) and the two `net_lag` placeholder fields; `GameState` grew the run lifecycle, `can_advance_floor()` / `last_advance_refusal`, `apply_remote_floor()` and `biome_for_index()`. All are additions — nothing was renamed or removed, and every one is listed as a judgment call in its decision.
- `scenes/player/player.tscn` (Dev A's scene) gained the `.:is_downed` replicated property and `scenes/player/player.gd` its two-line `request_revive` forwarding body, both **flagged for Dev A's review** rather than asked about, because the stub's own comment named networking as the week-3 filler and there is nowhere else the flag can be replicated. No other `.tscn` was touched.
- No `project.godot` setting, Input Map entry, `Events` signal signature, `scripts/data/` Resource definition, save-schema field, CI config or `addons/` file changed in week 3.
- Stale-claim sweep at this checkpoint: the `Player.request_revive` "still a stub" notes, the W3-B5 "console work untouched" note, decision 25's "Handle for G12" prescription (superseded — `floor <n>` walks through `next_floor()` deliberately), and the test/smoke counts in the HANDOFF header, command block and footer were each checked against the tree and corrected or dated.

Cut list actions (should be empty)
- none — the placeholder-backed pieces (lane-B floor layout, placeholder biome, read-only `net_lag` placeholder, placeholder interactable art, generated placeholder font/SFX) are tracked swaps with named owners, not cuts. Nothing from the design doc was dropped.

Next week risks
- Every Week 4 item that consumes Dev A's lane is still unlanded: elites with affixes (W4-A1), `SpawnDirector` v2 (W4-A2), SHRINE room placement (W4-A3), the combat-event emission set (W4-A4) and the Blacksmith damage tier (W4-A5). The effect system, statuses, relics, loot and HUD are therefore built against the spec interfaces plus `tests/helpers/` doubles, with a test-only emitter covering W4-A4's events (that emitter landed 2026-10-20 as `tests/helpers/event_emitter.gd`, G8 — one named method per bus signal, asserting coverage against the spec's table); if that emission lands mid-week, the swap is mechanical but every harness case should be re-run against the real emitter.
- The Week 4 checkpoint's headline claim — a pathological proc build holding 60 FPS — needs a real window; if only headless runs are possible on this machine, the recorded numbers are labelled with the method and the limitation rather than claimed as a bare pass (BRIEF Assumption 5).
- The Shrine room has no placement rule until W4-A3, so the Shrine interactable and the relic-pick flow are testable headlessly but cannot be reached by walking a generated floor; smoke step 4 stays blocked until that lands.
- `week-2` and `week-3` are both untagged. If Dev A's lanes land later, both weeks should be tagged retroactively before the mid-project gate, or the milestones explicitly re-scoped with a human.
