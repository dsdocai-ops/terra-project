# Sinkhole

2D isometric action roguelike. Godot 4.7.2, GDScript, Compatibility renderer. Two developers, 12 weeks, 1 to 4 player online co-op built in from week 1.

## Read these first

| Document | What it is |
|---|---|
| [SINKHOLE_SPEC.md](SINKHOLE_SPEC.md) | Design doc v3. Locked. Defines every system, content count, and milestone. Scope is never narrowed without a human decision |
| [specs/CAPABILITY_MAP.md](specs/CAPABILITY_MAP.md) | Module ids, dependencies, owners, build order. Every task, branch, and PR names a module id from here |
| [specs/SPEC-project.md](specs/SPEC-project.md) | Engineering contract: stack, commands, folder structure, code style, testing, boundaries, git workflow |
| `specs/SPEC-<module-id>.md` | One spec per module: objective, interfaces, success criteria |

## Commands

Godot binary: `C:\Godot\Godot_v4.7.2-stable_win64.exe`. Full list in [SPEC-project.md](specs/SPEC-project.md#commands).

```powershell
godot --headless --path . --import                                                        # import, surfaces parse errors
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit   # all tests
godot --path . -- --host        # co-op instance 1
godot --path . -- --join=127.0.0.1   # co-op instance 2
```

Godot MCP tools (`launch_editor`, `run_project`, `get_debug_output`) are available and preferred for opening the editor and reading runtime errors.

## Hard rules

- Strict static typing. `untyped_declaration` is an error.
- Content is data: a `.tres` plus an optional effect script. Dialogue and lore are JSON. Never a new system for one item.
- Gameplay logic runs on the host only. Every stateful script's doc comment says who owns it and how it syncs.
- Never `Engine.time_scale`. Use `TimeManager`.
- Never edit base stats. Use `StatBlock` modifiers.
- Tests ship in the same PR as the code. Never skip or delete a failing test.
- Ask before changing `project.godot`, Input Map, autoloads, `scripts/data/` Resource definitions, `Events` signals, save schema, CI, or addons.
- Never edit a `.tscn` owned by the other lane without asking. Ownership table in [SPEC-project.md](specs/SPEC-project.md#ownership).
- Any PR touching sync runs the two-instance smoke test first.
- Nothing from the design doc is cut without an explicit human decision recorded in the capability map.

## Workflow

Branch `feat/<module-id>-<desc>` off `main`, PR into `main`, CI green, review required for shared systems. Weekly build tagged `week-N`. Spec-driven: spec, plan, tasks, implement, each gated by human review.
