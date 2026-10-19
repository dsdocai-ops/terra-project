"""Structural (regex) extractor for Godot projects: .gd, .tscn, .tres, project.godot.
Emits graphify AST-shaped nodes/edges. Only edges whose both endpoints exist are emitted.
Usage: python gd_extract.py <project_root> <out_json>
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
OUT = Path(sys.argv[2])
EXCLUDE_DIRS = {"addons", ".godot", "graphify-out", ".git"}

nodes = {}
edges = []
edge_seen = set()


def rel(p):
    return p.relative_to(ROOT).as_posix()


def fid(relpath, suffix=""):
    stem = re.sub(r"\.(gd|tscn|tres)$", "", relpath)
    return re.sub(r"[^A-Za-z0-9]+", "_", stem).strip("_") + suffix


def add_node(nid, label, src, line, kind, **meta):
    if nid in nodes:
        return nodes[nid]
    md = {"language": "gdscript", "kind": kind}
    md.update({k: v for k, v in meta.items() if v not in (None, False, [], "")})
    n = {"id": nid, "label": label, "file_type": "code", "source_file": src,
         "source_location": "L%d" % line, "metadata": md, "_origin": "ast"}
    nodes[nid] = n
    return n


def add_edge(s, t, relation, src, line, context=None):
    if s == t or s not in nodes or t not in nodes:
        return
    key = (s, t, relation, context)
    if key in edge_seen:
        return
    edge_seen.add(key)
    e = {"source": s, "target": t, "relation": relation, "confidence": "EXTRACTED",
         "source_file": src, "source_location": "L%d" % line, "weight": 1.0, "_origin": "ast"}
    if context:
        e["context"] = context
    edges.append(e)


def walk(exts):
    out = []
    for p in ROOT.rglob("*"):
        if p.suffix in exts and p.is_file() and not (set(p.relative_to(ROOT).parts[:-1]) & EXCLUDE_DIRS):
            out.append(p)
    return sorted(out)


def strip_strings_comments(line):
    code = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
    code = re.sub(r"'(?:\\.|[^'\\])*'", "''", code)
    return code.split("#", 1)[0]


def first_doc(lines):
    doc = []
    for ln in lines[:40]:
        s = ln.strip()
        if s.startswith("##"):
            doc.append(s.lstrip("#").strip())
        elif doc:
            break
    return " ".join(doc)[:200] if doc else None


gd_files, scn_files, tres_files = walk({".gd"}), walk({".tscn"}), walk({".tres"})
res_path_to_id = {}

# ---- register file nodes first so cross-file resolution works ----
for p in gd_files:
    r = rel(p)
    add_node(fid(r), p.name, r, 1, "file")
    res_path_to_id["res://" + r] = fid(r)
for p in scn_files:
    r = rel(p)
    add_node(fid(r, "_tscn"), p.name, r, 1, "scene")
    res_path_to_id["res://" + r] = fid(r, "_tscn")
for p in tres_files:
    r = rel(p)
    add_node(fid(r, "_tres"), p.name, r, 1, "resource")
    res_path_to_id["res://" + r] = fid(r, "_tres")

# ---- project.godot: autoloads + main scene ----
autoloads = {}
proj = ROOT / "project.godot"
if proj.exists():
    PNID = "project_godot"
    add_node(PNID, "project.godot", "project.godot", 1, "project_config")
    section = None
    for i, line in enumerate(proj.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        s = line.strip()
        if s.startswith("["):
            section = s.strip("[]")
            continue
        if section == "autoload":
            m = re.match(r'([A-Za-z_]\w*)="\*?(res://[^"]+)"', s)
            if m and m.group(2) in res_path_to_id:
                tid = res_path_to_id[m.group(2)]
                autoloads[m.group(1)] = tid
                nodes[tid]["metadata"]["autoload"] = m.group(1)
                add_edge(PNID, tid, "registers_autoload", "project.godot", i, m.group(1))
        elif section == "application":
            m = re.match(r'run/main_scene="(res://[^"]+)"', s)
            if m and m.group(1) in res_path_to_id:
                add_edge(PNID, res_path_to_id[m.group(1)], "main_scene", "project.godot", i)

# ---- pass 1: GDScript structure ----
scripts = {}
class_by_name = {}
FUNC_RE = re.compile(r"(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(")
for p in gd_files:
    r = rel(p)
    nid = fid(r)
    lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
    info = {"id": nid, "rel": r, "class_name": None, "extends": None, "funcs": {}, "signals": {},
            "inner": {}, "lines": lines, "bodies": [], "owner_of_line": {}}
    doc = first_doc(lines)
    if doc:
        nodes[nid]["metadata"]["doc"] = doc
    cur_inner = None
    pending_rpc = False
    for i, line in enumerate(lines, 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip("\t "))
        m = re.match(r"class_name\s+([A-Za-z_]\w*)", s)
        if m and indent == 0:
            info["class_name"] = m.group(1)
            class_by_name[m.group(1)] = nid
            nodes[nid]["label"] = m.group(1)
            nodes[nid]["metadata"]["class_name"] = m.group(1)
            continue
        m = re.match(r'extends\s+("?)([^\s"]+)\1', s)
        if m and indent == 0:
            info["extends"] = m.group(2)
            nodes[nid]["metadata"]["extends"] = m.group(2)
            continue
        m = re.match(r"class\s+([A-Za-z_]\w*)(?:\s+extends\s+(\S+?))?\s*:", s)
        if m and indent == 0:
            cname, cid = m.group(1), "%s_%s" % (nid, m.group(1))
            add_node(cid, cname, r, i, "inner_class", extends=m.group(2))
            add_edge(nid, cid, "contains", r, i)
            cur_inner = (cname, cid)
            info["inner"][cname] = {"id": cid, "extends": m.group(2)}
            continue
        if indent == 0:
            cur_inner = None
        owner = cur_inner[1] if cur_inner else nid
        if s.startswith("@rpc"):
            pending_rpc = True
        m = FUNC_RE.match(s)
        if m:
            fname = m.group(1)
            fnid = "%s_%s" % (owner, fname)
            add_node(fnid, fname + "()", r, i, "function", static=s.startswith("static"), rpc=pending_rpc,
                     owner_class=(cur_inner[0] if cur_inner else info["class_name"]))
            add_edge(owner, fnid, "defines", r, i)
            info["funcs"][(owner, fname)] = fnid
            info["bodies"].append((fnid, i, indent))
            pending_rpc = False
            continue
        m = re.match(r"signal\s+([A-Za-z_]\w*)", s)
        if m:
            sid = "%s_sig_%s" % (owner, m.group(1))
            add_node(sid, "signal " + m.group(1), r, i, "signal")
            add_edge(owner, sid, "defines", r, i)
            info["signals"][m.group(1)] = sid
            continue
    for fnid, start, ind in info["bodies"]:
        j = start
        while j < len(lines):
            ln = lines[j]
            st = ln.strip()
            if st and not st.startswith("#"):
                if len(ln) - len(ln.lstrip("\t ")) <= ind:
                    break
            info["owner_of_line"][j + 1] = fnid
            j += 1
    scripts[r] = info

# ---- pass 2: resolution ----
QUAL_CALL = re.compile(r"(?<![\w.])([A-Z][A-Za-z0-9_]*)\.([A-Za-z_]\w*)\s*\(")
QUAL_SIG = re.compile(r"(?<![\w.])([A-Z][A-Za-z0-9_]*)\.([A-Za-z_]\w*)\.(emit|connect|disconnect|is_connected)\s*\(")
LOCAL_SIG = re.compile(r"(?<![\w.])([A-Za-z_]\w*)\.(emit|connect)\s*\(")
BARE_CALL = re.compile(r"(?<![\w.])([A-Za-z_]\w*)\s*\(")
CONNECT_CB = re.compile(r"\.connect\(\s*([A-Za-z_]\w*)")
PRELOAD = re.compile(r'\b(?:preload|load)\(\s*"(res://[^"]+)"')
TYPE_REF = re.compile(r"(?<![\w.])([A-Z][A-Za-z0-9_]*)\b")
SKIP_BARE = {"if", "elif", "while", "for", "match", "return", "await", "not", "and", "or", "in", "is", "func",
             "print", "assert", "super", "range", "len", "str", "int", "float", "bool"}
id_to_info = {}


def resolve_name(name, info):
    if name in autoloads:
        return autoloads[name], "autoload"
    if name in class_by_name:
        return class_by_name[name], "class"
    if name in info["inner"]:
        return info["inner"][name]["id"], "inner"
    return None, None


for r, info in scripts.items():
    id_to_info[info["id"]] = info

for r, info in scripts.items():
    nid = info["id"]
    ext = info["extends"]
    if ext:
        if ext.startswith("res://") and ext in res_path_to_id:
            add_edge(nid, res_path_to_id[ext], "inherits", r, 1)
        elif ext in class_by_name:
            add_edge(nid, class_by_name[ext], "inherits", r, 1)
    for cname, inner in info["inner"].items():
        if inner["extends"] and inner["extends"] in class_by_name:
            add_edge(inner["id"], class_by_name[inner["extends"]], "inherits", r, 1)
    for i, line in enumerate(info["lines"], 1):
        if not line.strip() or line.strip().startswith("#"):
            continue
        src_node = info["owner_of_line"].get(i, nid)
        for m in PRELOAD.finditer(line):
            tgt = res_path_to_id.get(m.group(1))
            if tgt:
                add_edge(nid, tgt, "imports", r, i, "preload")
        code = strip_strings_comments(line)
        # a definition header is not a call site: drop "func name" / "signal name"
        code = re.sub(r"^\s*(?:static\s+)?(?:func|signal)\s+[A-Za-z_]\w*", "", code)
        consumed = set()
        for m in QUAL_SIG.finditer(code):
            q, sig, op = m.groups()
            tid, _ = resolve_name(q, info)
            if tid:
                tinfo = id_to_info.get(tid)
                sid = tinfo["signals"].get(sig) if tinfo else None
                if sid:
                    add_edge(src_node, sid, "emits" if op == "emit" else "connects", r, i)
                    consumed.add(m.start())
        for m in LOCAL_SIG.finditer(code):
            name, op = m.groups()
            if name in info["signals"]:
                add_edge(src_node, info["signals"][name], "emits" if op == "emit" else "connects", r, i)
        for m in CONNECT_CB.finditer(code):
            cb = m.group(1)
            for (owner, fname), fnid in info["funcs"].items():
                if fname == cb:
                    add_edge(src_node, fnid, "connects", r, i, "callback")
                    break
        for m in QUAL_CALL.finditer(code):
            q, meth = m.groups()
            if m.start() in consumed:
                continue
            tid, how = resolve_name(q, info)
            if not tid:
                continue
            if meth == "new":
                add_edge(src_node, tid, "instantiates", r, i)
            elif "%s_%s" % (tid, meth) in nodes:
                add_edge(src_node, "%s_%s" % (tid, meth), "calls", r, i, "call")
            else:
                add_edge(nid, tid, "references", r, i, how)
        for m in BARE_CALL.finditer(code):
            name = m.group(1)
            if name in SKIP_BARE:
                continue
            owner = src_node.rsplit("_", 1)[0] if src_node != nid else nid
            for cand in ("%s_%s" % (owner, name), "%s_%s" % (nid, name)):
                if cand in nodes and nodes[cand]["metadata"].get("kind") == "function" and cand != src_node:
                    add_edge(src_node, cand, "calls", r, i, "call")
                    break
            if name in class_by_name:
                add_edge(nid, class_by_name[name], "references", r, i, "class")
        for m in TYPE_REF.finditer(code):
            name = m.group(1)
            tid, how = resolve_name(name, info)
            if tid and tid != nid and how in ("class", "autoload"):
                add_edge(nid, tid, "references", r, i, how)

# ---- scenes and resources ----
EXT_RES = re.compile(r'\[ext_resource type="(\w+)"[^\]]*?path="(res://[^"]+)"[^\]]*?id="([^"]+)"\]')
NODE_HDR = re.compile(r'\[node name="([^"]+)"(?: type="(\w+)")?(?: parent="([^"]*)")?(?: instance=ExtResource\("([^"]+)"\))?')
SUB_RES = re.compile(r'\[sub_resource type="(\w+)" id="([^"]+)"\]')
for p in scn_files + tres_files:
    r = rel(p)
    is_scene = p.suffix == ".tscn"
    nid = fid(r, "_tscn" if is_scene else "_tres")
    lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
    ext = {}
    node_count = 0
    cur_block = None
    rep_props = {}
    sync_nodes = {}
    m0 = re.match(r'\[gd_resource type="(\w+)"', lines[0]) if lines else None
    if m0:
        nodes[nid]["metadata"]["resource_type"] = m0.group(1)
    for i, line in enumerate(lines, 1):
        s = line.strip()
        m = EXT_RES.match(s)
        if m:
            ext[m.group(3)] = (m.group(1), m.group(2), i)
            continue
        m = SUB_RES.match(s)
        if m:
            cur_block = ("sub", m.group(1), m.group(2), i)
            if m.group(1) == "SceneReplicationConfig":
                rep_props[m.group(2)] = []
            continue
        m = NODE_HDR.match(s)
        if m:
            node_count += 1
            name, ntype, parent, inst = m.groups()
            cur_block = ("node", name, i)
            if inst and inst in ext and ext[inst][1] in res_path_to_id:
                add_edge(nid, res_path_to_id[ext[inst][1]], "instantiates", r, i, name)
            continue
        if s == "[resource]":
            cur_block = ("resource", i)
            continue
        m = re.match(r'script = ExtResource\("([^"]+)"\)', s)
        if m and m.group(1) in ext and ext[m.group(1)][1] in res_path_to_id:
            if cur_block and cur_block[0] == "node":
                ctx = cur_block[1]
            elif cur_block and cur_block[0] == "sub":
                ctx = cur_block[2]
            else:
                ctx = "resource"
            add_edge(nid, res_path_to_id[ext[m.group(1)][1]], "uses_script", r, i, ctx)
            continue
        if cur_block and cur_block[0] == "sub" and cur_block[1] == "SceneReplicationConfig":
            m = re.match(r'properties/\d+/path = NodePath\("([^"]+)"\)', s)
            if m:
                rep_props[cur_block[2]].append(m.group(1))
        m = re.match(r'replication_config = SubResource\("([^"]+)"\)', s)
        if m and cur_block and cur_block[0] == "node":
            sync_nodes[m.group(1)] = cur_block[1]
    for rid, props in rep_props.items():
        cnid = "%s_%s" % (nid, rid)
        add_node(cnid, rid, r, 1, "replication_config", properties=props, synchronizer_node=sync_nodes.get(rid))
        add_edge(nid, cnid, "defines", r, 1)
    for eid, (etype, path, line) in ext.items():
        tgt = res_path_to_id.get(path)
        if tgt and not any(e["source"] == nid and e["target"] == tgt for e in edges):
            add_edge(nid, tgt, "imports", r, line, etype)
    if is_scene:
        nodes[nid]["metadata"]["node_count"] = node_count

OUT.write_text(json.dumps({"nodes": list(nodes.values()), "edges": edges, "input_tokens": 0, "output_tokens": 0},
                          indent=2, ensure_ascii=False), encoding="utf-8")
print("GD extract: %d nodes, %d edges" % (len(nodes), len(edges)))
print("kinds:", dict(Counter(n["metadata"]["kind"] for n in nodes.values())))
print("relations:", dict(Counter(e["relation"] for e in edges)))
