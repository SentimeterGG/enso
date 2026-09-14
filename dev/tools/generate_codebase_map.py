#!/usr/bin/env python3
"""Visual codebase map generator — grid + mindmap modes.

Mindmap mode (default) builds a relation graph:
  - every .gd file = a block (file name + leading-`#` header explanation)
  - every .tscn scene = a scene node
  - edges are derived automatically from:
      1. .tscn [ext_resource] script attachments + PackedScene instances
      2. .tscn [connection] signal wiring (resolved to the scripts behind nodes)
      3. .gd code refs: preload/load scene, change_scene_to_file,
         ChartData/ChartParser/GestureRecognizer class usage,
         $/root song-time reads, recognizer SubResource use, in-code calls
      4. reverse flows: each uses/call edge gets a twin from the target's
         `# RETURN:` header comment (draw.gd <- returns accuracy <- recognizer.gd)

Usage:
    python3 dev/tools/generate_codebase_map.py [--root DIR] [--out FILE] [--mode mindmap|grid] [--format html|txt]

Defaults (when run from this repo):
    root = nearest ancestor containing project.godot
    out  = <root>/dev/tools/codebase_map.html (or .txt with --format txt)
"""

from __future__ import annotations

import argparse
import datetime
import html
import json
import math
import pathlib
import re

# ---------------------------------------------------------------- headers


def extract_header_comment(path: pathlib.Path) -> str:
    """Read leading `#` comments from the very start of the file.

    `# RETURN:` lines belong to extract_returns() and are skipped here
    so the description stays clean.
    """
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return "Could not read file."
    parts: list[str] = []
    started = False
    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        if not stripped:
            if started:
                break
            continue
        if stripped.startswith("#!"):
            continue
        if stripped.startswith("#"):
            cleaned = stripped.lstrip("#").strip()
            if cleaned.upper().startswith("RETURN"):
                started = True
                continue  # handled by extract_returns()
            started = True
            if cleaned:
                parts.append(cleaned)
            continue
        break
    if not parts:
        return "No header comment found."
    return " ".join(parts)


def extract_returns(path: pathlib.Path) -> str:
    """Read `# RETURN: ...` line(s) from the leading comment block.

    Convention (top of each .gd file, right after the description):
        # RETURN: accuracy score (0-100) for compare, shape name for guess
    A bare `# RETURN` may also head a run of `# ...` continuation lines.
    Returns "" when absent.
    """
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    collected: list[str] = []
    in_return = False
    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        if not stripped:
            if collected:
                break
            continue
        if not stripped.startswith("#") or stripped.startswith("#!"):
            break  # first code line: header block is over
        cleaned = stripped.lstrip("#").strip()
        if cleaned.upper().startswith("RETURN"):
            rest = re.sub(r"(?i)^RETURN\s*:?", "", cleaned).strip()
            if rest:
                collected.append(rest)
            in_return = True
            continue
        if in_return:
            # continuation line of a bare `# RETURN` header
            if re.match(r"^[A-Z_]+:", cleaned):
                break
            collected.append(cleaned)
        # ordinary description lines don't end the scan (RETURN may follow them)
    return "; ".join(c for c in collected if c)


def short_returns(text: str, limit: int = 48) -> str:
    text = " ".join(text.split())
    return text if len(text) <= limit else text[:limit].rstrip() + "…"


def extract_gd_meta(path: pathlib.Path) -> dict[str, str]:
    meta = {"class_name": "", "extends": ""}
    try:
        for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines()[
            :30
        ]:
            s = raw_line.strip()
            if s.startswith("class_name "):
                bits = s.split()
                meta["class_name"] = bits[1] if len(bits) > 1 else ""
            elif s.startswith("extends "):
                bits = s.split()
                meta["extends"] = bits[1] if len(bits) > 1 else ""
    except OSError:
        pass
    return meta


def res_to_rel(res: str, root: pathlib.Path) -> str | None:
    """res://scripts/game/game.gd -> scripts/game/game.gd (None if outside project)."""
    if not res.startswith("res://"):
        return None
    return res[len("res://") :]


# ---------------------------------------------------------------- tscn parsing

EXT_RE = re.compile(r'\[ext_resource[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"')
EXT_RE2 = re.compile(r'\[ext_resource[^\]]*id="([^"]+)"[^\]]*path="([^"]+)"')
NODE_RE = re.compile(r'\[node\s+name="([^"]+)"([^\]]*)\]')
CONN_RE = re.compile(
    r'\[connection\s+signal="([^"]+)"\s+from="([^"]*)"\s+to="([^"]*)"\s+method="([^"]+)"'
)
SUB_SCRIPT_RE = re.compile(r'script\s*=\s*ExtResource\("([^"]+)"\)')
INSTANCE_RE = re.compile(r'instance\s*=\s*ExtResource\("([^"]+)"\)')
NODE_PATHS_RE = re.compile(r"node_paths\s*=\s*PackedStringArray\(([^)]*)\)")


def parse_tscn(path: pathlib.Path) -> dict:
    text = path.read_text(encoding="utf-8", errors="replace")
    ext: dict[str, str] = {}  # ext id -> res:// path
    ext_type: dict[str, str] = {}
    for m in re.finditer(r"\[ext_resource([^\]]*)\]", text):
        body = m.group(1)
        pm = re.search(r'[\s]path="([^"]+)"', body)
        im = re.search(r'[\s]id="([^"]+)"', body)
        tm = re.search(r'[\s]type="([^"]+)"', body)
        if pm and im:
            ext[im.group(1)] = pm.group(1)
            ext_type[im.group(1)] = tm.group(1) if tm else ""
    # sub_resources that carry a script (e.g. recognizer Resource in draw.tscn)
    sub_scripts: list[str] = []
    for m in re.finditer(r"\[sub_resource([^\]]*)\](.*?)(?=\n\[|\Z)", text, re.S):
        mm = SUB_SCRIPT_RE.search(m.group(2))
        if mm and mm.group(1) in ext:
            sub_scripts.append(ext[mm.group(1)])

    nodes: list[dict] = []
    # split into [node ...] blocks so body lines (script = ..., instance = ...)
    # below each header are attributed to the right node
    node_blocks = re.split(r"(?=\[node\s)", text)
    for block in node_blocks:
        m = NODE_RE.match(block)
        if not m:
            continue
        name, rest = m.group(1), m.group(2)
        pm = re.search(r'parent="([^"]*)"', rest)
        parent = pm.group(1) if pm else None  # None = scene root
        full = (
            name
            if parent in (None, ".")
            else parent.strip("./") + "/" + name
            if parent
            else name
        )
        if parent == ".":
            full = name
        sm = SUB_SCRIPT_RE.search(block)
        script_res = ext.get(sm.group(1)) if sm else None
        im = INSTANCE_RE.search(block)
        instance_res = ext.get(im.group(1)) if im else None
        nodes.append(
            {
                "name": name,
                "parent": parent,
                "full": full,
                "script": script_res,
                "instance": instance_res,
            }
        )
    conns: list[dict] = []
    for m in CONN_RE.finditer(text):
        conns.append(
            {
                "signal": m.group(1),
                "from": m.group(2),
                "to": m.group(3),
                "method": m.group(4),
            }
        )
    return {
        "ext": ext,
        "ext_type": ext_type,
        "nodes": nodes,
        "conns": conns,
        "sub_scripts": sub_scripts,
    }


# ---------------------------------------------------------------- graph build


def build_graph(root: pathlib.Path):
    gd_files = sorted(
        p
        for p in root.rglob("*.gd")
        if ".godot" not in p.parts and ".git" not in p.parts and p.is_file()
    )
    tscn_files = sorted(
        p
        for p in root.rglob("*.tscn")
        if ".godot" not in p.parts and ".git" not in p.parts and p.is_file()
    )

    gd_rel = {f.relative_to(root).as_posix() for f in gd_files}
    nodes: dict[str, dict] = {}
    edges: dict[tuple, dict] = {}

    def add_edge(a: str, b: str, label: str, kind: str):
        if a == b or not a or not b:
            return
        key = (a, b, label)
        if key not in edges:
            edges[key] = {"a": a, "b": b, "label": label, "kind": kind}

    # gd nodes (blocks with name + header explanation + RETURN contract)
    for f in gd_files:
        rel = f.relative_to(root).as_posix()
        nodes[rel] = {
            "id": rel,
            "type": "gd",
            "title": f.name,
            "sub": rel,
            "desc": extract_header_comment(f),
            "returns": extract_returns(f),
            "meta": extract_gd_meta(f),
        }

    # scene nodes
    tscn_data: dict[str, dict] = {}
    for f in tscn_files:
        rel = f.relative_to(root).as_posix()
        data = parse_tscn(f)
        tscn_data[rel] = data
        attached = sorted(
            {res_to_rel(n["script"], root) for n in data["nodes"] if n["script"]}
        )
        attached = [a for a in attached if a]
        desc = (
            ("Attaches " + ", ".join(a.split("/")[-1] for a in attached))
            if attached
            else "Scene (no script attached)"
        )
        inst = sorted(
            {
                res_to_rel(ext, root)
                for eid, ext in data["ext"].items()
                if data["ext_type"].get(eid) == "PackedScene"
            }
        )
        inst = [i for i in inst if i]
        if inst:
            desc += " · instances " + ", ".join(i.split("/")[-1] for i in inst)
        nodes[rel] = {
            "id": rel,
            "type": "scene",
            "title": f.name,
            "sub": rel,
            "desc": desc,
            "meta": {},
        }

    # 1) scene -> gd attachments, 2) scene -> scene instances, sub_resource uses
    for rel, data in tscn_data.items():
        seen_scripts: set[str] = set()
        for n in data["nodes"]:
            if n["script"]:
                g = res_to_rel(n["script"], root)
                if g and g in nodes and g not in seen_scripts:
                    seen_scripts.add(g)
                    add_edge(rel, g, "attaches", "attach")
            if n["instance"]:
                s = res_to_rel(n["instance"], root)
                if s and s in nodes:
                    add_edge(rel, s, "instances", "instance")
        for s in data["sub_scripts"]:
            g = res_to_rel(s, root)
            if g and g in nodes:
                add_edge(rel, g, "uses resource", "resource")

        # 3) signal connections resolved to scripts
        # map node-full-path -> gd rel (direct script, or instanced scene root script)
        node_to_gd: dict[str, str] = {}
        for n in data["nodes"]:
            g = None
            if n["script"]:
                g = res_to_rel(n["script"], root)
            elif n["instance"]:
                inst_rel = res_to_rel(n["instance"], root)
                if inst_rel and inst_rel in tscn_data:
                    for nn in tscn_data[inst_rel]["nodes"]:
                        if nn["parent"] is None and nn["script"]:
                            g = res_to_rel(nn["script"], root)
                            break
            if g and g in nodes:
                node_to_gd[n["full"]] = g
                node_to_gd[n["name"]] = node_to_gd.get(n["name"], g)
        # scene root script (the `to="."` target)
        root_gd = node_to_gd.get(
            next((n["full"] for n in data["nodes"] if n["parent"] is None), ""), ""
        )

        def resolve(ref: str) -> str:
            if ref == ".":
                return root_gd or ""
            return node_to_gd.get(ref, node_to_gd.get(ref.split("/")[-1], ""))

        for c in data["conns"]:
            src, dst = resolve(c["from"]), resolve(c["to"])
            if src and dst and src in nodes and dst in nodes:
                add_edge(src, dst, f"signal: {c['signal']}", "signal")

    # 4-7) code refs inside .gd files
    code_cache: dict[str, str] = {}
    for f in gd_files:
        rel = f.relative_to(root).as_posix()
        try:
            code_cache[rel] = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            code_cache[rel] = ""
    for f in gd_files:
        rel = f.relative_to(root).as_posix()
        code = code_cache[rel]
        if not code:
            continue
        for m in re.finditer(r'(?:preload|load)\("(res://[^"]+)"\)', code):
            g = res_to_rel(m.group(1), root)
            if g and g in nodes:
                label = "spawns beat_point" if "beat_point" in g else "loads"
                add_edge(rel, g, label, "load")
        for m in re.finditer(r'change_scene_to_file\("(res://[^"]+)"\)', code):
            g = res_to_rel(m.group(1), root)
            if g and g in nodes:
                add_edge(rel, g, "opens scene", "scene_change")
        if "ChartParser" in code and rel != "scripts/chart/chart_parser.gd":
            add_edge(rel, "scripts/chart/chart_parser.gd", "uses ChartParser", "class")
        if re.search(r"\bChartData\b", code) and rel not in (
            "scripts/chart/chart_data.gd",
            "scripts/chart/chart_parser.gd",
        ):
            add_edge(rel, "scripts/chart/chart_data.gd", "uses ChartData", "class")
        if "GestureRecognizer" in code and rel != "scripts/draw_manager/recognizer.gd":
            add_edge(
                rel, "scripts/draw_manager/recognizer.gd", "uses recognizer", "class"
            )
        if (
            '$"/root/game/music"' in code
            or "$'/root/game/music'" in code
            or "/root/game/music" in code
        ):
            if "scenes/game.tscn" in nodes:
                add_edge(rel, "scenes/game.tscn", "reads song time", "node_ref")

    # curated: draw.gd compares against target_shape owned by game.gd
    if "scripts/draw_manager/draw.gd" in nodes and "scripts/game/game.gd" in nodes:
        add_edge(
            "scripts/draw_manager/draw.gd",
            "scripts/game/game.gd",
            "scores vs target_shape",
            "node_ref",
        )
    # in-code call chains the .tscn wiring doesn't show:
    #   game.gd -> note_manager.spawn() -> beat_column.spawn_beat()
    if (
        "scripts/game/game.gd" in nodes
        and "scripts/note_manager/note_manager.gd" in nodes
    ):
        if re.search(
            r"note_manager\.spawn\s*\(", code_cache.get("scripts/game/game.gd", "")
        ):
            add_edge(
                "scripts/game/game.gd",
                "scripts/note_manager/note_manager.gd",
                "spawns notes",
                "call",
            )
    if "scripts/note_manager/beat/beat_column.gd" in nodes:
        if re.search(
            r"beat_column\.spawn_beat\s*\(",
            code_cache.get("scripts/note_manager/note_manager.gd", ""),
        ):
            add_edge(
                "scripts/note_manager/note_manager.gd",
                "scripts/note_manager/beat/beat_column.gd",
                "forwards spawn",
                "call",
            )
    # level_item.gd clicks through to list.select(index)
    if "scripts/ui/level_selector/level_item.gd" in nodes:
        if re.search(
            r"\.select\s*\(",
            code_cache.get("scripts/ui/level_selector/level_item.gd", ""),
        ):
            add_edge(
                "scripts/ui/level_selector/level_item.gd",
                "scripts/ui/level_selector/level_list.gd",
                "calls select()",
                "call",
            )
    # who enables the draw layer per scene (game / main menu / level selector)
    for src in (
        "scripts/game/game.gd",
        "scripts/ui/main_menu.gd",
        "scripts/ui/level_selector/level_selector.gd",
    ):
        if src in nodes and re.search(
            r"draw_manager\.(start|stop)\s*\(", code_cache.get(src, "")
        ):
            add_edge(src, "scripts/draw_manager/draw.gd", "controls drawing", "call")
    # reverse flows: every "A uses/calls B" edge gets a "B returns X to A" twin,
    # with X read from B's `# RETURN:` header comment. E.g.
    #   draw.gd -> uses -> recognizer.gd
    #   draw.gd <- returns accuracy <- recognizer.gd
    for e in list(edges.values()):
        if e["kind"] not in ("class", "call"):
            continue
        giver = nodes.get(e["b"], {})
        ret = giver.get("returns", "")
        if not ret or giver.get("type") != "gd":
            continue
        add_edge(e["b"], e["a"], f"returns {short_returns(ret)}", "returns")
    return nodes, list(edges.values())


# ---------------------------------------------------------------- per-scene duplication
# A script used by 2+ scenes (e.g. draw.gd) is duplicated so each scene owns
# its own block:  ENSO -> game.tscn -> draw.gd @game
#                 ENSO -> level_selector.tscn -> draw.gd @levels ...

TOP_SHORT = {
    "scenes/game.tscn": "game",
    "scenes/level_selector.tscn": "levels",
    "scenes/main_menu.tscn": "menu",
}


def duplicate_shared(nodes: dict, edges: list) -> tuple[dict, list, dict]:
    top_scenes = [s for s in TOP_SHORT if s in nodes]
    # context of each top scene: directly attached scripts + component scenes
    # it instances + scripts attached to those components (+beat chain pseudo-member)
    ctx: dict[str, dict] = {s: {"members": set(), "via": {}} for s in top_scenes}
    for e in edges:
        if (
            e["kind"] == "attach"
            and e["a"] in ctx
            and nodes.get(e["b"], {}).get("type") == "gd"
        ):
            ctx[e["a"]]["members"].add(e["b"])
            ctx[e["a"]]["via"][e["b"]] = "attaches"
        elif (
            e["kind"] == "instance"
            and e["a"] in ctx
            and nodes.get(e["b"], {}).get("type") == "scene"
        ):
            ctx[e["a"]]["members"].add(e["b"])
            ctx[e["a"]]["via"][e["b"]] = "instances"
    # one level deeper: scripts attached to instanced component scenes
    # (attach) or baked in as sub-resources (resource, e.g. recognizer) —
    # both count as belonging to the scene, so multi-scene ones get duplicated
    for s in top_scenes:
        for comp in sorted(ctx[s]["members"]):
            if nodes.get(comp, {}).get("type") != "scene":
                continue
            for e in edges:
                if (
                    e["a"] == comp
                    and e["kind"] in ("attach", "resource")
                    and nodes.get(e["b"], {}).get("type") == "gd"
                ):
                    ctx[s]["members"].add(e["b"])
                    ctx[s]["via"][e["b"]] = comp.split("/")[-1]
    # beat_point chain belongs to the game scene's story (spawned in code)
    if "scenes/game.tscn" in ctx:
        for m in ("scenes/beat_point.tscn", "scripts/note_manager/beat/beat_point.gd"):
            if m in nodes:
                ctx["scenes/game.tscn"]["members"].add(m)
                ctx["scenes/game.tscn"]["via"][m] = "spawned"

    # shared = member of 2+ contexts (component scenes + instance scripts land here;
    # pure libraries like recognizer/ChartParser only link via resource/class edges
    # so they stay single shared nodes)
    contexts_of: dict[str, set[str]] = {}
    for s in top_scenes:
        for m in ctx[s]["members"]:
            contexts_of.setdefault(m, set()).add(s)
    shared = {m for m, ss in contexts_of.items() if len(ss) > 1}

    def expand(nid: str) -> list[str]:
        if nid in shared:
            return [f"{nid}@ {TOP_SHORT[s]}" for s in sorted(contexts_of[nid])]
        return [nid]

    for orig in sorted(shared):
        for s in sorted(contexts_of[orig]):
            short = TOP_SHORT[s]
            nid = f"{orig}@ {short}"
            dup = dict(nodes[orig])
            dup["id"] = nid
            dup["copy_of"] = orig
            dup["copy_scene"] = s
            dup["copy_via"] = ctx[s]["via"].get(orig, "")
            nodes[nid] = dup
    for orig in shared:
        del nodes[orig]

    def ctxs_containing(nid: str) -> set[str]:
        if nid in top_scenes:  # a top scene owns exactly its own copies
            return {nid}
        if nodes[nid].get("copy_scene"):
            return {nodes[nid]["copy_scene"]}
        return set(contexts_of.get(nid, set()))

    new_edges: list[dict] = []
    seen: set[tuple] = set()
    for e in edges:
        a_opts, b_opts = expand(e["a"]), expand(e["b"])
        if len(a_opts) == 1 and len(b_opts) == 1:
            pairs = [(a_opts[0], b_opts[0])]
        elif len(a_opts) > 1 and len(b_opts) == 1:
            ca = ctxs_containing(b_opts[0])
            targets = (
                [a for a in a_opts if nodes[a]["copy_scene"] in ca] if ca else a_opts
            )
            pairs = [(a, b_opts[0]) for a in targets]
        elif len(a_opts) == 1 and len(b_opts) > 1:
            ca = ctxs_containing(a_opts[0])
            targets = (
                [b for b in b_opts if nodes[b]["copy_scene"] in ca] if ca else b_opts
            )
            pairs = [(a_opts[0], b) for b in targets]
        else:
            common = {nodes[a]["copy_scene"] for a in a_opts} & {
                nodes[b]["copy_scene"] for b in b_opts
            }
            pairs = []
            for s in common:
                a = next(x for x in a_opts if nodes[x]["copy_scene"] == s)
                b = next(x for x in b_opts if nodes[x]["copy_scene"] == s)
                pairs.append((a, b))
        for a, b in pairs:
            label, kind = e["label"], e["kind"]
            if kind in ("attach", "instance") and a in top_scenes and "@ " in b:
                label = f"via {nodes[b].get('copy_via') or kind}"
                kind = "owns"
            key = (a, b, label)
            if a != b and key not in seen:
                seen.add(key)
                new_edges.append({"a": a, "b": b, "label": label, "kind": kind})
    new_edges = [e for e in new_edges if e["a"] in nodes and e["b"] in nodes]
    return nodes, new_edges, {"contexts": ctx, "shared": shared, "top": top_scenes}


def members_union(members: dict[str, set[str]]) -> set[str]:
    out: set[str] = set()
    for v in members.values():
        out |= v
    return out


def layout_mindmap_old(nodes: dict, edges: list) -> dict:
    scenes = sorted(
        [n for n in nodes.values() if n["type"] == "scene"], key=lambda d: d["id"]
    )
    gds = sorted(
        [n for n in nodes.values() if n["type"] == "gd"], key=lambda d: d["id"]
    )
    pos: dict[str, tuple[float, float]] = {"hub": (0, 0)}
    # inner ring: scenes
    R1 = 360.0
    # isolated shape_point last so main scenes spread nicely
    scenes_sorted = sorted(
        scenes, key=lambda d: (d["id"].endswith("shape_point.tscn"), d["id"])
    )
    for i, s in enumerate(scenes_sorted):
        ang = 2 * math.pi * i / max(len(scenes_sorted), 1) - math.pi / 2
        pos[s["id"]] = (R1 * math.cos(ang), R1 * math.sin(ang))
        s["_ang"] = ang
    # adjacency gd -> scenes
    adj: dict[str, set[str]] = {g["id"]: set() for g in gds}
    for e in edges:
        for a, b in ((e["a"], e["b"]), (e["b"], e["a"])):
            if a in adj and b in nodes and nodes[b]["type"] == "scene":
                adj[a].add(b)
    # gd angle = mean of linked scene angles (fallback: game.tscn / spread)
    game_ang = next(
        (s["_ang"] for s in scenes_sorted if s["id"].endswith("game.tscn")), 0.0
    )
    R2 = 720.0
    angles: dict[str, float] = {}
    for g in gds:
        linked = [nodes[s]["_ang"] for s in adj[g["id"]] if "_ang" in nodes[s]]
        if linked:
            xs = sum(math.cos(a) for a in linked) / len(linked)
            ys = sum(math.sin(a) for a in linked) / len(linked)
            angles[g["id"]] = math.atan2(ys, xs)
        else:
            angles[g["id"]] = game_ang
    # declutter: sort by angle, enforce min gap
    order = sorted(gds, key=lambda g: angles[g["id"]])
    min_gap = 2 * math.pi / max(len(order), 1) * 0.85
    for i in range(1, len(order)):
        prev, cur = order[i - 1]["id"], order[i]["id"]
        # handle wraparound-safe forward enforcement
        if angles[cur] - angles[prev] < 0:
            angles[cur] += 2 * math.pi
        if angles[cur] - angles[prev] < min_gap * 0.55:
            angles[cur] = angles[prev] + min_gap * 0.55
    for g in gds:
        a = angles[g["id"]] % (2 * math.pi)
        # push class-only helpers slightly inward so they sit near game.gd
        r = (
            R2 - 130
            if g["id"]
            in ("scripts/chart/chart_data.gd", "scripts/chart/chart_parser.gd")
            else R2
        )
        pos[g["id"]] = (r * math.cos(a), r * math.sin(a))
    return pos


# ---------------------------------------------------------------- shared BFS (chains from ENSO)


def compute_bfs(nodes: dict, edges: list):
    """Undirected BFS from the hub. Returns (adj, degree, layer, parent,
    border, branch, top_here). `parent` gives every node its dependency
    chain back to ENSO; `branch` its top-scene lane (None = global)."""
    from collections import deque

    adj: dict[str, set[str]] = {}
    degree: dict[str, int] = {}

    def link(a: str, b: str) -> None:
        adj.setdefault(a, set()).add(b)
        adj.setdefault(b, set()).add(a)

    for e in edges:
        # scene_change links two different scenes (menu <-> selector) and
        # returns edges mirror an existing forward edge — both are real edges,
        # but neither may hijack BFS parents/chains into another lane
        if e["kind"] not in ("scene_change", "returns"):
            link(e["a"], e["b"])
        degree[e["a"]] = degree.get(e["a"], 0) + 1
        degree[e["b"]] = degree.get(e["b"], 0) + 1
    for nid, n in nodes.items():
        if (
            n["type"] == "scene"
            and "@ " not in nid
            and (nid in TOP_SHORT or degree.get(nid, 0) == 0)
        ):
            link("hub", nid)

    layer: dict[str, int] = {"hub": 0}
    parent: dict[str, str | None] = {"hub": None}
    border: list[str] = ["hub"]
    dq = deque(["hub"])
    while dq:
        cur = dq.popleft()
        for nb in sorted(adj.get(cur, set())):
            if nb == "hub" or nb not in nodes or nb in layer:
                continue
            layer[nb] = layer[cur] + 1
            parent[nb] = cur
            border.append(nb)
            dq.append(nb)
    for nid in nodes:  # unreachable safety net
        if nid not in layer:
            layer[nid] = 1
            parent[nid] = "hub"
            border.append(nid)

    top_here = [s for s in TOP_SHORT if s in nodes]
    branch: dict[str, str | None] = {"hub": None}
    for nid in border:
        if nid == "hub":
            continue
        branch[nid] = nid if nid in top_here else branch.get(parent[nid] or "")
    return adj, degree, layer, parent, border, branch, top_here


# ---------------------------------------------------------------- layout (chain-tree mindmap)
# Layers = graph distance from ENSO, left to right, exactly like:
#   ENSO -> game.tscn -> game.gd -> chart_data.gd -> ...
# Each top scene gets its own horizontal lane so wires stay local.


def layout_mindmap(nodes: dict, edges: list, info: dict | None = None) -> dict:
    info = info or {}
    X_STEP, Y_GAP, LANE_GAP = 430.0, 230.0, 150.0

    adj, degree, layer, parent, border, branch, top_here = compute_bfs(nodes, edges)

    lane_order: list = [s for s in TOP_SHORT if s in top_here] + [None]
    lanes: dict = {
        s: [nid for nid in border if nid != "hub" and branch.get(nid) == s]
        for s in lane_order
    }

    # local layout per lane, then stack lanes top to bottom
    ys: dict[str, float] = {}
    lane_bounds: dict = {}
    for s in lane_order:
        by_lev: dict[int, list[str]] = {}
        for nid in lanes[s]:
            by_lev.setdefault(layer[nid], []).append(nid)
        local: dict[str, float] = {}
        if s is not None:
            local[s] = 0.0  # top scene anchors its lane
        for lev in sorted(by_lev):
            group = [nid for nid in by_lev[lev] if nid != s]

            def key(nid: str) -> float:
                prefs = [
                    local[n]
                    for n in adj.get(nid, set())
                    if layer.get(n) == lev - 1 and n in local
                ]
                if prefs:
                    return sum(prefs) / len(prefs)
                p = parent.get(nid)
                return local.get(p or "", 0.0)

            group.sort(key=lambda nid: (key(nid), nid))
            keys = [key(n) for n in group]
            cur: list[float] = []
            for i, k in enumerate(keys):
                cur.append(k if i == 0 else max(k, cur[-1] + Y_GAP))
            if keys:
                shift = sum(keys) / len(keys) - sum(cur) / len(cur)
                cur = [y + shift for y in cur]
            for nid, y in zip(group, cur):
                local[nid] = y
        ys.update(local)
        vals = list(local.values())
        lane_bounds[s] = (min(vals), max(vals)) if vals else (0.0, 0.0)

    y_cursor, lane_offset = 0.0, {}
    for s in lane_order:
        lo, hi = lane_bounds[s]
        lane_offset[s] = y_cursor - lo
        y_cursor += (hi - lo) + LANE_GAP
    shift_all = -(y_cursor - LANE_GAP) / 2  # center whole stack on the hub
    pos: dict[str, tuple[float, float]] = {"hub": (0.0, 0.0)}
    for s in lane_order:
        for nid in lanes[s]:
            pos[nid] = (layer[nid] * X_STEP, ys[nid] + lane_offset[s] + shift_all)
    return pos


# ---------------------------------------------------------------- HTML builders


def build_mindmap_html(nodes: dict, edges: list, pos: dict, root: pathlib.Path) -> str:
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    COLORS = {
        "game": "#ffd479",
        "menu": "#8fd0ff",
        "chart": "#b8e6a0",
        "draw": "#e6a0c8",
        "note": "#c8b8ff",
        "ui": "#9fe6d8",
        "misc": "#c9d1dd",
        "scene": "#7fe0c3",
        "hub": "#ffffff",
    }

    def color(n: dict) -> str:
        i = n["id"]
        if n["type"] in ("hub", "scene"):
            return COLORS["scene"] if n["type"] == "scene" else COLORS["hub"]
        if "game.gd" in i or "accuracy" in i:
            return COLORS["game"]
        if (
            "main_menu" in i
            or "level_select" in i
            or "level_item" in i
            or "level_list" in i
        ):
            return COLORS["ui"]
        if "chart" in i:
            return COLORS["chart"]
        if "draw" in i or "recognizer" in i:
            return COLORS["draw"]
        if "note_manager" in i or "beat" in i:
            return COLORS["note"]
        if "mouse_overlay" in i:
            return COLORS["misc"]
        return COLORS["misc"]

    jnodes = [
        {
            "id": n["id"],
            "type": n["type"],
            "title": n["title"],
            "sub": n["sub"],
            "desc": n["desc"][:280],
            "color": color(n),
            "returns": n.get("returns", ""),
            "copy": (
                f"@{n['copy_scene'].split('/')[-1].replace('.tscn', '')}"
                if n.get("copy_scene")
                else ""
            ),
            "copy_via": n.get("copy_via", ""),
            "x": round(pos.get(n["id"], (0, 0))[0], 1),
            "y": round(pos.get(n["id"], (0, 0))[1], 1),
        }
        for n in nodes.values()
    ]
    jnodes.append(
        {
            "id": "hub",
            "type": "hub",
            "title": "ENSO",
            "sub": root.name,
            "desc": "Godot rhythm-drawing game — click any block to highlight its relations.",
            "color": COLORS["hub"],
            "returns": "",
            "copy": "",
            "copy_via": "",
            "x": 0,
            "y": 0,
        }
    )
    # hub spokes only to top-level scenes + isolated scenes (copies anchor via their scene)
    degree: dict[str, int] = {}
    for e in edges:
        degree[e["a"]] = degree.get(e["a"], 0) + 1
        degree[e["b"]] = degree.get(e["b"], 0) + 1
    hub_links = [
        s["id"]
        for s in nodes.values()
        if s["type"] == "scene"
        and "@ " not in s["id"]
        and (s["id"] in TOP_SHORT or degree.get(s["id"], 0) == 0)
    ]
    jedges = [
        {"a": e["a"], "b": e["b"], "label": e["label"], "kind": e["kind"]}
        for e in edges
    ]
    for s in hub_links:
        jedges.append({"a": "hub", "b": s, "label": "", "kind": "hub"})

    data_json = json.dumps({"nodes": jnodes, "edges": jedges})
    return f"""<!DOCTYPE html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Codebase Mindmap — {html.escape(root.name)}</title>
<style>
*{{box-sizing:border-box}} body{{margin:0;font-family:'Segoe UI',system-ui,sans-serif;background:#0b0e13;color:#e8eaf0;overflow:hidden}}
#bar{{position:fixed;top:0;left:0;right:0;z-index:10;display:flex;gap:10px;align-items:center;padding:10px 14px;background:rgba(13,17,23,.92);border-bottom:1px solid #232936;flex-wrap:wrap}}
#bar h1{{font-size:15px;margin:0}} #bar .sub{{font-size:12px;color:#9aa3b2}}
#search{{flex:1;min-width:180px;max-width:340px;padding:7px 12px;border-radius:8px;border:1px solid #2a2f3a;background:#171b22;color:#fff}}
#bar button{{background:#1c2330;border:1px solid #334052;color:#cfe3ff;border-radius:8px;padding:6px 10px;cursor:pointer;font-size:12px}}
#legend{{position:fixed;left:12px;bottom:12px;z-index:10;background:rgba(15,19,26,.92);border:1px solid #2a3040;border-radius:10px;padding:8px 12px;font-size:11.5px;color:#aeb7c6}}
#legend b{{color:#fff}} .dot{{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:5px}}
#viewport{{position:fixed;inset:52px 0 0 0;overflow:hidden;cursor:grab}}
#world{{position:absolute;left:50%;top:50%;width:0;height:0}}
svg#wires{{position:absolute;overflow:visible;pointer-events:none}}
.node{{position:absolute;width:272px;transform:translate(-50%,-50%);background:linear-gradient(180deg,#1a1f29,#141821);border:1px solid #2a3040;border-radius:13px;padding:10px 12px;box-shadow:0 6px 22px rgba(0,0,0,.5);cursor:grab;font-size:12px}}
.node.scene{{width:230px;border-style:dashed}}
.node.hub{{width:210px;text-align:center;border:2px solid #fff}}
.node .t{{font-family:Consolas,monospace;font-weight:700;font-size:13.5px;margin-bottom:2px;word-break:break-all}}
.node .p{{font-family:Consolas,monospace;font-size:10.5px;color:#8b94a5;margin-bottom:6px;word-break:break-all}}
.node .d{{font-size:11.8px;line-height:1.45;color:#d3d9e4}}
.node .r{{margin-top:6px;font-size:11px;line-height:1.4;color:#ffcf9e;border-top:1px dashed #3a3f2a;padding-top:6px}}
.node .c{{display:inline-block;margin-top:7px;font-size:10.5px;background:#2a2410;border:1px solid #8a6d1c;color:#ffd479;border-radius:20px;padding:2px 9px}}
.node.dim{{opacity:.18}} .node.active{{border-color:#fff;box-shadow:0 0 0 2px #fff3}}
.edge-label{{font-size:10.5px;fill:#9fb3cc;background:#000}}
path.wire{{fill:none;stroke:#3a4a63;stroke-width:1.6}}
path.wire.signal{{stroke:#ffd479}} path.wire.attach{{stroke:#7fe0c3}} path.wire.scene_change{{stroke:#ff9d9d}}
path.wire.owns{{stroke:#5aa8ff}} path.wire.call{{stroke:#c8b8ff}} path.wire.class{{stroke:#b8e6a0}} path.wire.load{{stroke:#5aa8ff}}
path.wire.returns{{stroke:#ff9d5c;stroke-dasharray:6 4}}
path.wire.dim{{opacity:.12}} path.wire.hot{{stroke:#fff;stroke-width:2.6}}
#tip{{position:fixed;right:12px;bottom:12px;z-index:10;max-width:300px;background:rgba(15,19,26,.94);border:1px solid #2a3040;border-radius:10px;padding:10px 12px;font-size:12px;color:#c7cfdd}}
</style></head><body>
<div id="bar"><h1>🧠 Codebase Mindmap</h1><span class="sub">{len([n for n in nodes.values() if n["type"] == "gd"])} scripts · {len([n for n in nodes.values() if n["type"] == "scene"])} scenes · {len(edges)} relations · {now}</span>
<input id="search" placeholder="🔍 filter blocks..."><button id="reset">⟲ reset view</button><button id="labels">🏷️ labels on/off</button></div>
<div id="legend"><b>Relations</b> (from .tscn + .gd parsing)<br>
<span class="dot" style="background:#5aa8ff"></span>owns/instances
&nbsp;<span class="dot" style="background:#ffd479"></span>signal &nbsp;<span class="dot" style="background:#ff9d9d"></span>opens scene
&nbsp;<span class="dot" style="background:#b8e6a0"></span>uses class &nbsp;<span class="dot" style="background:#c8b8ff"></span>calls
&nbsp;<span class="dot" style="background:#ff9d5c"></span>returns (reverse flow, dashed)
<br>🔁 <b>@game / @levels / @menu</b> = same script duplicated so each scene owns its copy
<br>chains flow left → right: ENSO → scene → script → its dependencies · drag · zoom · click to isolate</div>
<div id="viewport"><div id="world"><svg id="wires"></svg></div></div>
<div id="tip">Click a block to highlight its relations.<br>Edges come from scene attachments, instances, signal connections and code refs.</div>
<script>const DATA = {data_json};</script>
<script>
const world=document.getElementById('world'), wires=document.getElementById('wires'), vp=document.getElementById('viewport');
let scale=0.62, ox=0, oy=0, showLabels=true;
const byId={{}}; DATA.nodes.forEach(n=>byId[n.id]=n);
const NS='http://www.w3.org/2000/svg';
function el(tag,attrs){{const e=document.createElementNS(NS,tag);for(const k in attrs)e.setAttribute(k,attrs[k]);return e;}}
// create node divs
const divs={{}};
DATA.nodes.forEach(n=>{{
  const d=document.createElement('div'); d.className='node '+n.type; d.dataset.id=n.id;
  const copyChip=n.copy?`<div><span class="c">🔁 ${{n.copy}} · via ${{n.copy_via||'scene'}}</span></div>`:'';
  const retLine=n.returns?`<div class="r">↩ returns: ${{n.returns.replace(/</g,'&lt;')}}</div>`:'';
  d.innerHTML=`<div class="t" style="color:${{n.color}}">${{n.type==='scene'?'🎬 ':n.type==='hub'?'⭐ ':'🧱 '}}${{n.title}}${{n.copy?' '+n.copy:''}}</div><div class="p">${{n.sub}}</div><div class="d">${{n.desc.replace(/</g,'&lt;')}}</div>${{retLine}}${{copyChip}}`;
  d.style.left=n.x+'px'; d.style.top=n.y+'px'; world.appendChild(d); divs[n.id]=d; n._el=d;
  d.addEventListener('pointerdown',ev=>{{ev.stopPropagation();startDrag(ev,n);}});
  d.addEventListener('click',ev=>{{ev.stopPropagation();isolate(n.id);}});
}});
function drawWires(hot){{
  wires.innerHTML='';
  const R=4000; wires.setAttribute('width',R*2); wires.setAttribute('height',R*2);
  wires.style.left=-R+'px'; wires.style.top=-R+'px';
  // spread parallel edges (same node pair, e.g. uses + its returns twin)
  // across stacked curves so their labels don't sit on top of each other
  const lanes={{}};
  DATA.edges.forEach(e=>{{
    const k=[e.a,e.b].sort().join('|');
    e._lane=(lanes[k]=(lanes[k]||0)+1)-1;
  }});
  const laneCount={{}}; DATA.edges.forEach(e=>{{laneCount[[e.a,e.b].sort().join('|')]=e._lane+1;}});
  DATA.edges.forEach(e=>{{
    const A=byId[e.a],B=byId[e.b]; if(!A||!B)return;
    const x1=A.x+R,y1=A.y+R,x2=B.x+R,y2=B.y+R;
    // canonical orientation for the offset: a -> b twin and its b -> a twin
    // must share one normal, otherwise the mirrored direction flips the
    // offset back onto the exact same curve and they collapse into one line
    const cx1=e.a<e.b?x1:x2,cy1=e.a<e.b?y1:y2,cx2=e.a<e.b?x2:x1,cy2=e.a<e.b?y2:y1;
    const dx=cx2-cx1,dy=cy2-cy1,L=Math.hypot(dx,dy)||1;
    // spread parallel wires perpendicular to the wire direction: spreading
    // only vertically keeps twins overlapped when the blocks sit above
    // each other, so the offset goes along the wire's normal instead
    const spread=(e._lane-(laneCount[[e.a,e.b].sort().join('|')]-1)/2)*34;
    const mx=(x1+x2)/2+(-dy/L)*spread,my=(y1+y2)/2-40+(dx/L)*spread;
    const p=el('path',{{d:`M${{x1}},${{y1}} Q${{mx}},${{my}} ${{x2}},${{y2}}`,class:'wire '+e.kind+(hot&&!(e.a===hot||e.b===hot)?' dim':'')+(hot&&(e.a===hot||e.b===hot)?' hot':'')}});
    wires.appendChild(p);
    if(showLabels&&e.label&&(!hot||e.a===hot||e.b===hot)){{
      const t=el('text',{{x:mx,y:my-4,'text-anchor':'middle',class:'edge-label'}}); t.textContent=e.label; wires.appendChild(t);
    }}
  }});
}}
function apply(){{world.style.transform=`translate(${{ox}}px,${{oy}}px) scale(${{scale}})`;}}
function isolate(id){{
  const near=new Set([id]);
  DATA.edges.forEach(e=>{{if(e.a===id)near.add(e.b); if(e.b===id)near.add(e.a);}});
  DATA.nodes.forEach(n=>n._el.classList.toggle('dim',!near.has(n.id)));
  DATA.nodes.forEach(n=>n._el.classList.toggle('active',n.id===id));
  drawWires(id);
  const n=byId[id];
  document.getElementById('tip').innerHTML=`<b>${{n.title}}</b> <span style="color:#8b94a5">${{n.sub}}</span><br>${{n.desc.replace(/</g,'&lt;')}}<br><br><span style="color:#8b94a5">click background to clear</span>`;
}}
function clearIso(){{DATA.nodes.forEach(n=>n._el.classList.remove('dim','active'));drawWires(null);}}
// pan / zoom
let pan=null;
vp.addEventListener('pointerdown',e=>{{pan={{x:e.clientX-ox,y:e.clientY-oy}};vp.setPointerCapture(e.pointerId);}});
vp.addEventListener('pointermove',e=>{{if(pan){{ox=e.clientX-pan.x;oy=e.clientY-pan.y;apply();}}}});
vp.addEventListener('pointerup',()=>pan=null);
vp.addEventListener('click',clearIso);
vp.addEventListener('wheel',e=>{{e.preventDefault();scale=Math.min(1.6,Math.max(.2,scale*(e.deltaY<0?1.1:0.9)));apply();}},{{passive:false}});
function startDrag(ev,n){{
  ev.preventDefault(); const sx=ev.clientX,sy=ev.clientY,ox0=n.x,oy0=n.y;
  const mv=e=>{{n.x=ox0+(e.clientX-sx)/scale;n.y=oy0+(e.clientY-sy)/scale;n._el.style.left=n.x+'px';n._el.style.top=n.y+'px';drawWires(document.querySelector('.node.active')?.dataset.id||null);}};
  const up=()=>{{removeEventListener('pointermove',mv);removeEventListener('pointerup',up);}};
  addEventListener('pointermove',mv);addEventListener('pointerup',up);
}}
document.getElementById('reset').onclick=()=>{{fitView();clearIso();}};
document.getElementById('labels').onclick=()=>{{showLabels=!showLabels;drawWires(document.querySelector('.node.active')?.dataset.id||null);}};
document.getElementById('search').addEventListener('input',e=>{{
  const q=e.target.value.toLowerCase();
  DATA.nodes.forEach(n=>{{n._el.style.display=(n.title+n.sub+n.desc).toLowerCase().includes(q)?'':'none';}});
}});
function fitView(){{
  const xs=DATA.nodes.map(n=>n.x), ys=DATA.nodes.map(n=>n.y);
  const minx=Math.min(...xs)-200, maxx=Math.max(...xs)+200;
  const miny=Math.min(...ys)-170, maxy=Math.max(...ys)+170;
  const w=vp.clientWidth||1400, h=vp.clientHeight||700;
  scale=Math.max(0.12,Math.min(1.0,Math.min(w/(maxx-minx),h/(maxy-miny))));
  ox=-(minx+maxx)/2*scale; oy=-(miny+maxy)/2*scale; apply();
}}
fitView();drawWires(null);
</script></body></html>"""


def build_grid_html(items: list[dict], root: pathlib.Path) -> str:
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    groups: dict[str, list[dict]] = {}
    for it in sorted(items, key=lambda d: d["rel"]):
        groups.setdefault(it["group"], []).append(it)
    parts = [
        f"""<!DOCTYPE html><html><head><meta charset="utf-8"><title>Codebase Map — {html.escape(root.name)}</title>
<style>*{{box-sizing:border-box}}body{{font-family:'Segoe UI',system-ui;background:#0f1115;color:#e8eaf0;margin:0;padding:28px}}
header,#search,section{{max-width:1100px;margin:0 auto}}#search{{width:100%;margin:16px auto;display:block;padding:10px 14px;border-radius:10px;border:1px solid #2a2f3a;background:#171b22;color:#fff}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:14px}}.block{{background:#171c25;border:1px solid #2a3040;border-radius:14px;padding:14px}}
.fname{{font-family:Consolas,monospace;color:#ffd479;font-weight:700}}.path{{font-size:11px;color:#9aa3b2}}.desc{{font-size:13px}}.ret{{font-size:12px;color:#ffcf9e;margin-top:6px}}</style></head><body>
<header><h1>🗺️ Codebase Map — {html.escape(str(root))}</h1><div>{len(items)} files · {now}</div></header>
<input id="search" placeholder="🔍 filter..."/>"""
    ]
    for g, blocks in groups.items():
        parts.append(f"<section><h2>📁 {html.escape(g)}</h2><div class='grid'>")
        for b in blocks:
            ret = (
                f"<div class='ret'>↩ returns: {html.escape(b['returns'])}</div>"
                if b.get("returns")
                else ""
            )
            parts.append(
                f"<div class='block'><div class='fname'>🧱 {html.escape(b['name'])}</div><div class='path'>{html.escape(b['rel'])}</div><div class='desc'>{html.escape(b['desc'])}</div>{ret}</div>"
            )
        parts.append("</div></section>")
    parts.append(
        """<script>document.getElementById('search').addEventListener('input',e=>{const q=e.target.value.toLowerCase();document.querySelectorAll('.block').forEach(b=>b.style.display=b.innerText.toLowerCase().includes(q)?'':'none');});</script></body></html>"""
    )
    return "\n".join(parts)


# ---------------------------------------------------------------- text export
# Same chains as the mindmap, in plain text:
#   ENSO <- game.tscn <- game.gd <- chart_data.gd
# followed by one description block per node (from each .gd header comment).


def short_label(nodes: dict, nid: str) -> str:
    n = nodes[nid]
    base = n["title"]
    if n.get("copy_scene"):
        base += f" @{TOP_SHORT.get(n['copy_scene'], n['copy_scene'])}"
    return base


def chain_of(parent: dict, nid: str) -> list[str]:
    chain, cur = [nid], nid
    while parent.get(cur):
        cur = parent[cur]  # type: ignore[index]
        chain.append(cur)
    return chain[::-1]


def build_txt(nodes: dict, edges: list, root: pathlib.Path) -> str:
    import datetime
    import textwrap

    adj, degree, layer, parent, border, branch, top_here = compute_bfs(nodes, edges)
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    n_gd = sum(1 for n in nodes.values() if n["type"] == "gd")
    n_sc = sum(1 for n in nodes.values() if n["type"] == "scene")
    hub_desc = "Godot rhythm-drawing game — root of the map."
    rule = "=" * 72
    thin = "-" * 72
    out: list[str] = [
        rule,
        f"ENSO — codebase map (text export, {now})",
        f"{n_gd} scripts + {n_sc} scenes, {len(edges)} relations",
        "chains read: ENSO <- scene <- script <- dependency",
        rule,
        "",
        "CHAINS",
        thin,
    ]
    lane_order: list = [s for s in TOP_SHORT if s in top_here] + [None]
    lane_names = {s: short_label(nodes, s) for s in lane_order if s is not None}
    lane_names[None] = "shared / global"
    for s in lane_order:
        members = sorted(
            [nid for nid in border if nid != "hub" and branch.get(nid) == s],
            key=lambda nid: (layer[nid], nid),
        )
        if not members:
            continue
        out += ["", f"[{lane_names[s]}]", ""]
        for nid in members:
            links = [
                ("ENSO" if c == "hub" else short_label(nodes, c))
                for c in chain_of(parent, nid)
            ]
            out.append(" <- ".join(links))
    out += [
        "",
        "",
        rule,
        "RETURNS (reverse flows)",
        thin,
        "each 'A uses B' line above has a twin below: what B gives back to A",
        "",
    ]
    for e in sorted(
        [e for e in edges if e["kind"] == "returns"], key=lambda d: (d["b"], d["a"])
    ):
        out.append(
            f"{short_label(nodes, e['b'])} <- {e['label']} <- {short_label(nodes, e['a'])}"
        )
    out += ["", "", rule, "DESCRIPTIONS", rule, ""]
    ordered = ["hub"] + sorted(
        [nid for nid in border if nid != "hub"],
        key=lambda nid: (lane_order.index(branch.get(nid)), layer[nid], nid),
    )
    for nid in ordered:
        if nid == "hub":
            title, sub, desc, ret = "ENSO", root.name, hub_desc, ""
        else:
            n = nodes[nid]
            title = short_label(nodes, nid)
            sub = n.get("copy_of", n["sub"])
            desc = n["desc"]
            ret = n.get("returns", "")
        out.append(f"description of {title} [{sub}]:")
        for line in textwrap.wrap(desc, width=100):
            out.append(f"  {line}")
        if ret:
            for line in textwrap.wrap(f"returns: {ret}", width=100):
                out.append(f"  {line}")
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate a visual codebase map.")
    ap.add_argument("--root", default="")
    ap.add_argument("--out", default="")
    ap.add_argument("--mode", default="mindmap", choices=["mindmap", "grid"])
    ap.add_argument(
        "--format",
        default="html",
        choices=["html", "txt"],
        help="html: interactive map, txt: chain + description dump",
    )
    args = ap.parse_args()

    if args.root:
        root = pathlib.Path(args.root).resolve()
    else:
        # walk up from this script until the project root (project.godot) is found
        here = pathlib.Path(__file__).resolve()
        root = next(
            (p for p in (here, *here.parents) if (p / "project.godot").is_file()),
            pathlib.Path.cwd(),
        )
    default_name = "codebase_map.html" if args.format == "html" else "codebase_map.txt"
    out = (
        pathlib.Path(args.out).resolve()
        if args.out
        else (root / "dev" / "tools" / default_name)
    )
    out.parent.mkdir(parents=True, exist_ok=True)

    if args.format == "txt":
        nodes, edges = build_graph(root)
        nodes, edges, info = duplicate_shared(nodes, edges)
        out.write_text(build_txt(nodes, edges, root), encoding="utf-8")
        n_gd = sum(1 for n in nodes.values() if n["type"] == "gd")
        n_sc = sum(1 for n in nodes.values() if n["type"] == "scene")
        print(
            f"Text map: {n_gd} scripts + {n_sc} scenes, {len(edges)} relations -> {out}"
        )
        return

    if args.mode == "grid":
        files = sorted(
            p
            for p in root.rglob("*.gd")
            if ".godot" not in p.parts and ".git" not in p.parts and p.is_file()
        )
        items = [
            {
                "name": f.name,
                "rel": f.relative_to(root).as_posix(),
                "group": str(f.parent.relative_to(root).as_posix()),
                "desc": extract_header_comment(f),
                "returns": extract_returns(f),
            }
            for f in files
        ]
        out.write_text(build_grid_html(items, root), encoding="utf-8")
        print(f"Grid map: {len(files)} files -> {out}")
        return

    nodes, edges = build_graph(root)
    nodes, edges, info = duplicate_shared(nodes, edges)
    pos = layout_mindmap(nodes, edges, info)
    out.write_text(build_mindmap_html(nodes, edges, pos, root), encoding="utf-8")
    n_gd = sum(1 for n in nodes.values() if n["type"] == "gd")
    n_sc = sum(1 for n in nodes.values() if n["type"] == "scene")
    print(f"Mindmap: {n_gd} scripts + {n_sc} scenes, {len(edges)} relations -> {out}")
    print(f"  duplicated per scene: {sorted(info['shared'])}")
    for e in sorted(edges, key=lambda d: (d["a"], d["b"])):
        print(f"  {e['a']} --[{e['label']}]--> {e['b']}")


if __name__ == "__main__":
    main()
