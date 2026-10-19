"""Rebuild graphify-out/ for this repo, including the GDScript / scene graph.

graphify has no GDScript extractor, so the stock pipeline misses every .gd,
.tscn and .tres file. This script runs the deterministic half of the pipeline
with gd_extract.py added, and merges in the doc extraction that /graphify
cached under graphify-out/cache/.

Run from the repo root:  python tools/graphify/rebuild.py [--force]
See tools/graphify/README.md for the full procedure.
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path.cwd()
HERE = Path(__file__).resolve().parent
OUT = ROOT / "graphify-out"
FORCE = "--force" in sys.argv[1:]
SPEC = Path(os.environ.get(
    "GRAPHIFY_SPEC",
    Path.home() / ".claude" / "skills" / "graphify" / "references" / "extraction-spec.md"))

if not (ROOT / "project.godot").exists():
    sys.exit("Run from the repo root (project.godot not found in %s)" % ROOT)

from graphify.analyze import god_nodes, suggest_questions, surprising_connections  # noqa: E402
from graphify.build import build_from_json  # noqa: E402
from graphify.cache import check_semantic_cache  # noqa: E402
from graphify.cluster import cluster, score_all  # noqa: E402
from graphify.detect import detect  # noqa: E402
from graphify.diagnostics import diagnose_extraction  # noqa: E402
from graphify.export import to_json  # noqa: E402
from graphify.extract import extract  # noqa: E402
from graphify.report import generate  # noqa: E402

OUT.mkdir(exist_ok=True)

# 1. Excludes: the GUT addon, binary assets, the icon. /graphify reads the same file.
shutil.copyfile(HERE / "graphify_build.json", OUT / ".graphify_build.json")
excludes = json.loads((HERE / "graphify_build.json").read_text(encoding="utf-8"))["excludes"]

# 2. Detect.
det = detect(ROOT, extra_excludes=excludes, gitignore=True)
print("detect: %d files (%d code, %d docs)" % (
    det["total_files"], len(det["files"].get("code", [])), len(det["files"].get("document", []))))

# 3. Structural extraction: graphify's own (shell, ps1) plus gd_extract.py (Godot).
builtin = extract([Path(f) for f in det["files"].get("code", [])], cache_root=ROOT, root=ROOT)
gd_json = OUT / ".graphify_gd.json"
subprocess.run([sys.executable, str(HERE / "gd_extract.py"), str(ROOT), str(gd_json)], check=True)
gd = json.loads(gd_json.read_text(encoding="utf-8"))
gd_json.unlink()
ast_ids = {n["id"] for n in gd["nodes"]}
ast_nodes = list(gd["nodes"]) + [n for n in builtin["nodes"] if n["id"] not in ast_ids]
ast_edges = gd["edges"] + builtin["edges"]
ast_ids = {n["id"] for n in ast_nodes}

# 4. Doc extraction, from the cache /graphify fills. Uncached docs are left out.
if not SPEC.exists():
    sys.exit("graphify extraction spec not found at %s; set GRAPHIFY_SPEC" % SPEC)
docs = [f for cat in ("document", "paper", "image") for f in det["files"].get(cat, [])]
sem_nodes, sem_edges, sem_hyper, uncached = check_semantic_cache(docs, root=str(ROOT), prompt_file=str(SPEC))
if uncached:
    print("WARNING: %d doc(s) have no cached extraction and are left out of the graph." % len(uncached))
    print("         Run /graphify . in Claude Code first (see README), then rerun this script:")
    for f in uncached:
        print("           " + Path(f).relative_to(ROOT).as_posix())

# Doc extraction may name a script by its extensionless id (tools_smoke_two) when
# graphify disambiguated the file node (tools_smoke_two_sh). Map unique aliases.
alias = {}
for n in ast_nodes:
    sf = n.get("source_file")
    if not sf or n.get("source_location") != "L1" or n["label"] != Path(sf).name:
        continue
    stem = "".join(c if c.isalnum() else "_" for c in Path(sf).with_suffix("").as_posix()).strip("_")
    alias.setdefault(stem, set()).add(n["id"])
alias = {k: next(iter(v)) for k, v in alias.items() if len(v) == 1 and k not in ast_ids}

seen = set(ast_ids)
nodes = list(ast_nodes)
for n in sem_nodes:
    n.setdefault("_origin", "semantic")
    if n["id"] not in seen:
        seen.add(n["id"])
        nodes.append(n)
edges = list(ast_edges)
dropped = 0
for e in sem_edges:
    e.setdefault("_origin", "semantic")
    e["source"] = alias.get(e["source"], e["source"])
    e["target"] = alias.get(e["target"], e["target"])
    if e["source"] in seen and e["target"] in seen:
        edges.append(e)
    else:
        dropped += 1
for h in sem_hyper:
    h["nodes"] = [alias.get(x, x) for x in h["nodes"] if alias.get(x, x) in seen]
if dropped:
    print("WARNING: dropped %d doc edge(s) whose endpoint no longer exists in the code." % dropped)
extraction = {"nodes": nodes, "edges": edges, "hyperedges": sem_hyper, "input_tokens": 0, "output_tokens": 0}

# 5. Build, cluster, report, export.
G = build_from_json(extraction, root=str(ROOT), directed=False)
communities = cluster(G)
cohesion = score_all(G, communities)
labels = {cid: "Community %d" % cid for cid in communities}
questions = suggest_questions(G, communities, labels)
if not to_json(G, communities, str(OUT / "graph.json"), force=FORCE):
    sys.exit("graphify refused to shrink graph.json (the existing graph has more nodes). "
             "Rerun with --force if files were deleted on purpose.")
report = generate(G, communities, cohesion, labels, god_nodes(G), surprising_connections(G, communities),
                  det, {"input": 0, "output": 0}, str(ROOT), suggested_questions=questions)
(OUT / "GRAPH_REPORT.md").write_text(report, encoding="utf-8")
subprocess.run([sys.executable, "-m", "graphify", "export", "html"], check=True, cwd=ROOT)

s = diagnose_extraction(extraction, directed=False, root=str(ROOT))
print("graph: %d nodes, %d edges, %d communities" % (G.number_of_nodes(), G.number_of_edges(), len(communities)))
print("health: %d missing-endpoint, %d dangling, %d self-loop edges" % (
    s.get("missing_endpoint_edges", 0), s.get("dangling_endpoint_edges", 0), s.get("self_loop_edges", 0)))
print("Communities are unnamed. Name them with: graphify label . --backend=claude-cli")
