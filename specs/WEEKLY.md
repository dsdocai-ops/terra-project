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
