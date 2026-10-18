# Spec: foundation

| | |
|---|---|
| Module id | `foundation` |
| Owner | Both |
| Weeks | 1 |
| Design doc | sections 5, 17, 18, 20 (week 1), 23 |
| Depends on | none |
| Depended on by | every module |

Project-wide rules in [SPEC-project.md](SPEC-project.md) apply.

## Objective

Turn the empty Godot project into the skeleton every other module builds on: correct project settings, the full Input Map, the folder tree, autoload stubs with their public API shapes, an isometric TileSet, a Y-sorted world scene with a camera, the GUT test harness, and CI. After this module, a developer on either lane can start their week 1 work without touching shared config.

## Scope

### Project settings (`project.godot`)

| Setting | Value |
|---|---|
| `application/config/name` | `Sinkhole` |
| `application/run/main_scene` | `res://scenes/main/main.tscn` |
| `display/window/size/viewport_width` / `height` | 960 / 540 |
| `display/window/size/window_width_override` / `height_override` | 1920 / 1080 (dev default; settings menu changes it later) |
| `display/window/stretch/mode` | `canvas_items` |
| `display/window/stretch/aspect` | `keep` |
| `display/window/stretch/scale_mode` | `integer` |
| `rendering/renderer/rendering_method` and `.mobile` | `gl_compatibility` |
| `rendering/textures/canvas_textures/default_texture_filter` | Nearest |
| `rendering/2d/snap/snap_2d_transforms_to_pixel` | true |
| `rendering/2d/snap/snap_2d_vertices_to_pixel` | true |
| `physics/common/physics_ticks_per_second` | 60 |
| `debug/gdscript/warnings/untyped_declaration` | Error |
| `debug/gdscript/warnings/inferred_declaration` | Ignore (decided 2026-10-18: Warn would flag every `:=`, which the code style uses throughout, and bury real warnings; Ignore is Godot's default for this reason) |
| `debug/gdscript/warnings/unsafe_*` (`property_access`, `method_access`, `cast`, `call_argument`) | Warn |
| `network/limits/debugger/max_chars_per_second` | 131072 (so debug console spam does not drop) |
| `layer_names/2d_physics/layer_1` to `layer_6` | `world`, `player`, `enemy`, `hitbox_player`, `hitbox_enemy`, `interactable` |

### Input Map

Every action from design doc section 5, exact names below. Keyboard and mouse bindings now, plus a controller binding for each gameplay action so controller play works from week 1 (controller menu navigation is stretch).

| Action name | Default |
|---|---|
| `move_up`, `move_down`, `move_left`, `move_right` | W S A D, left stick |
| `attack_light` | LMB, RT |
| `attack_heavy` | RMB, LT |
| `dodge` | Space, B |
| `class_skill` | Shift, LB |
| `swap_weapon` | wheel, Y |
| `weapon_1`, `weapon_2` | 1, 2 |
| `ability_1`, `ability_2`, `ability_3` | Q, R, V, face buttons X / A / RB |
| `ultimate` | X, L3+R3 |
| `relic_active_1`, `relic_active_2` | C, B, d-pad left / right |
| `potion` | E, d-pad up |
| `interact` | F, A (hold to revive) |
| `inventory` | Tab, Back |
| `ping` | MMB, d-pad down |
| `pause` | Esc, Start |
| `debug_console` | backtick |

Movement is 8-direction. Input vector is rotated onto isometric axes in `player-controller`, not here.

### Folder tree

Create every folder in [SPEC-project.md, Project structure](SPEC-project.md#project-structure) with a `.gdkeep` where empty, so both lanes see the same layout on day one.

### Autoload stubs

Register in this order (order matters for `_ready` dependencies): `Events`, `TimeManager`, `GameState`, `SaveManager`, `StoryManager`, `AudioManager`, `NetworkManager`.

Each stub is a typed script with the public API shape its owning module will fill in, every method bodied with `pass` or a trivial return, and a doc comment naming the owning module. The shapes are specified in the owning module's spec: `Events` in `SPEC-effect-system.md`, `TimeManager` in `SPEC-time-manager.md`, `GameState` in `SPEC-run-economy.md`, `SaveManager` in `SPEC-save-system.md`, `StoryManager` in `SPEC-story-dialogue.md`, `AudioManager` in `SPEC-art-audio.md`, `NetworkManager` in `SPEC-networking.md`. Stubs exist so consumers compile against the real names from week 1.

### Launch args

`main.gd` reads `OS.get_cmdline_user_args()`:

- `--host` : call `NetworkManager.host()` after the main scene loads and skip the menu.
- `--join=<ip>` : call `NetworkManager.join(ip)` and skip the menu.
- `--seed=<int>` : pass to `GameState` as forced run seed.
- No args: show main menu (menu itself is `ui-hud`; week 1 shows a placeholder with Host / Join buttons).

### Isometric TileSet

`assets/tilesets/placeholder_iso.tres`: TileSet with `tile_shape = Isometric`, `tile_layout = Diamond Down`, `tile_size = Vector2i(64, 32)`. Placeholder atlas with floor, wall, and pit tiles in three flat colors, plus physics layer on walls and a custom data layer `walkable: bool`. Real art replaces the atlas in `art-audio` without changing ids.

### World scene

`scenes/main/world.tscn`:

```
World (Node2D, y_sort_enabled = true)
  Floor (TileMapLayer, ground)
  Walls (TileMapLayer, y_sort_enabled, collision)
  Entities (Node2D, y_sort_enabled)      enemies, pickups, projectiles spawn here
  Players (Node2D, y_sort_enabled)       players spawn here (MultiplayerSpawner target, see SPEC-networking).
                                          Must be Y-sorted itself: Godot only interleaves a child container's
                                          children with its siblings when that container is Y-sorted too
  Camera (Camera2D)                       owned by player-controller
  FX (Node2D)                             particles, damage numbers, no y-sort
```

Helper `Iso` static class in `scripts/iso.gd`: `to_screen(tile: Vector2i) -> Vector2`, `to_tile(screen: Vector2) -> Vector2i`, `input_to_world(dir: Vector2) -> Vector2`.

`to_screen` / `to_tile` match `TileMapLayer.map_to_local` / `local_to_map` exactly for isometric diamond-down 64x32 (tile (0, 0) centers at (32, 16); +x runs down-right, +y down-left); tests assert this against a real layer.

`input_to_world` definition (decided 2026-10-18): cardinal inputs stay screen-aligned (W is screen up, D is screen right); diagonal inputs land on the tile axes (W+D moves along the -y tile axis, 26.565 degrees above horizontal on screen). The result keeps the input's magnitude, so all eight directions move at the same on-screen pixel speed. Consequence: the eight movement directions are the eight compass directions of the tile grid, not eight equal 45 degree steps. Facing sectors (`Facing`, player-controller) follow the same eight directions.

### Test harness and CI

- Vendor GUT 9.x into `addons/gut/`, enable plugin.
- `tests/unit/test_iso.gd`: round-trip `to_screen` / `to_tile` on a grid of tiles; `input_to_world` magnitudes.
- `tests/integration/test_scenes_load.gd`: instantiate every `.tscn` under `scenes/`.
- `tests/integration/test_data_loads.gd`: load every `.tres` under `data/` (empty in week 1, still runs).
- `.github/workflows/ci.yml`: on `pull_request` and `push` to `main`, install Godot 4.7.2 headless, `--import`, run GUT, fail on non-zero exit. Verify the chosen setup action publishes 4.7.2; if not, download the official Linux headless zip by URL.

## Interfaces provided

- `Iso` static helpers (above).
- Input action names (above). Other modules reference only these names.
- World scene node paths: `World/Entities`, `World/Players`, `World/FX`, `World/Camera`. Modules get them through `GameState.world` (set by `main.gd`), never by absolute path.
- Autoload names and ordering.

## Interfaces consumed

None.

## Data model

`.gdkeep` placeholders only. No Resources defined here; `scripts/data/` class files are created by their owning modules. Exception: `scripts/data/content_data.gd`, base class `ContentData extends Resource` with `@export var id: StringName` and `@export var display_name: String`, which every content Resource extends so data-driven tests can check ids match file names.

## Multiplayer ownership

Nothing stateful here. The world scene is loaded identically on every peer.

## Testing

- CI green on an empty-content project.
- `test_iso.gd`, `test_scenes_load.gd`, `test_data_loads.gd` pass.
- Manual: launch with `--host` and `--join=127.0.0.1` reaches the world scene on both (connection itself verified in `networking`).

## Success criteria

- [ ] `project.godot` matches the settings table; `untyped_declaration` is Error and the project still imports with zero warnings.
- [ ] Every Input Map action exists with keyboard/mouse and controller bindings.
- [ ] Folder tree matches SPEC-project exactly.
- [ ] All 7 autoloads registered in order, typed stubs with doc comments.
- [ ] Placeholder isometric TileSet renders a 20x20 diamond floor at 960x540 with crisp pixels and integer scaling at 1920x1080.
- [ ] `Iso` round-trip tests pass.
- [ ] CI runs import + GUT on a PR and reports status within 5 minutes.

## Open questions

- Exact GUT release and Godot setup action (resolved during week 1, recorded here).
