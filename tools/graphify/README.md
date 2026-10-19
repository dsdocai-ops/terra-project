# graphify knowledge graph

Tooling to build a [graphify](https://github.com/safishamsi/graphify) knowledge graph of this repo: code, scenes, specs, and plans in one queryable graph. Output goes to `graphify-out/`, which is gitignored. Each of us builds it locally.

graphify has no GDScript support. Out of the box it skips every `.gd`, `.tscn`, and `.tres` file. `gd_extract.py` fills that gap, and `rebuild.py` runs the whole pipeline with it.

| File | What it does |
|---|---|
| `gd_extract.py` | Regex extractor for `.gd`, `.tscn`, `.tres`, and `project.godot`. Emits functions, signals, emit/connect sites, cross-file calls, `extends`, `.new()`, preloads, scene instancing, attached scripts, autoloads, main scene, and `SceneReplicationConfig` properties. Skips `addons/` and `.godot/`. |
| `graphify_build.json` | Exclude list (GUT addon, `assets/`, `icon.svg`, this folder). `rebuild.py` copies it to `graphify-out/.graphify_build.json`, where `/graphify` also reads it. |
| `rebuild.py` | Detect, structural extraction (graphify's own plus `gd_extract.py`), merge with cached doc extraction, cluster, write `graph.json`, `GRAPH_REPORT.md`, `graph.html`. |

## One-time setup

```powershell
pip install graphifyy==0.9.92
graphify install --platform claude    # installs the /graphify skill into ~/.claude/skills/graphify
```

The graph was first built with 0.9.92. A newer version may change node ids or the cache format. If you upgrade, do a full rebuild (both steps below) rather than reusing an old `graphify-out/`.

`rebuild.py` needs the skill's extraction prompt at `~/.claude/skills/graphify/references/extraction-spec.md`, because the doc cache is keyed on it. If yours lives elsewhere, set `GRAPHIFY_SPEC` to its full path.

## Full rebuild

All commands run from the repo root.

### Step 1. Extract the docs (Claude Code, costs tokens)

Specs, plans, `CLAUDE.md`, and CI config are read by an LLM. graphify caches the result per file under `graphify-out/cache/`, so this step only re-reads docs that changed.

```powershell
python tools/graphify/rebuild.py    # first, so graphify-out/.graphify_build.json has the excludes
```

Then, in Claude Code at the repo root:

```
/graphify .
```

That run builds a graph without Godot code, which is expected. Its only job here is to fill the doc cache. The first full run of all 33 docs used about 370k tokens.

Skip step 1 when no `.md` or `.yml` file changed since your last build.

### Step 2. Build the full graph (no LLM, free)

```powershell
python tools/graphify/rebuild.py --force
```

`--force` is needed after step 1, or after any change that removes nodes. graphify refuses to overwrite a `graph.json` that has more nodes than the new one, and the step 1 graph or an old build can trip that check.

The script prints a health line. All three counts should be 0:

```
health: 0 missing-endpoint, 0 dangling, 0 self-loop edges
```

It also warns about any doc that has no cached extraction. Those docs are left out of the graph until you run step 1.

### Step 3. Name the communities (optional, costs tokens)

`rebuild.py` leaves communities as `Community 0`, `Community 1`, and so on. To name them:

```powershell
graphify label . --backend=claude-cli
graphify export html
```

## Using the graph

```powershell
graphify query "how does a player spawn on a client?"
graphify path "Main" "Player"
graphify explain "StateMachine"
```

Open `graphify-out/graph.html` in a browser for the interactive view. `graphify-out/GRAPH_REPORT.md` lists god nodes, surprising connections, and community cohesion.

## Do not use

- **`graphify update .` and `graphify watch .`** only re-extract file types graphify knows. They drop every Godot node, or refuse to write because the graph would shrink. Use `rebuild.py` instead.
- **`/graphify . --update`** has the same problem.

## Limits of `gd_extract.py`

It is regex-based, not a parser. Treat its edges as a good map, not ground truth.

- Calls resolve only through `class_name`, autoload names, inner classes, and same-script functions. A call on an untyped variable (`node.foo()`) is not linked.
- Signal edges cover `Name.signal.emit/connect` on autoloads and classes, and `signal.emit/connect` within one script. Connections made in the editor and saved in `.tscn` files are not read.
- `@rpc` functions are flagged in metadata. The repo has none yet.
- New Godot file types or folders outside `addons/` and `.godot/` are picked up automatically. To skip a folder, add it to `graphify_build.json`, and to `EXCLUDE_DIRS` in `gd_extract.py` if it contains `.gd` files.
