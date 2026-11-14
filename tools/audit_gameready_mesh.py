#!/usr/bin/env python3
"""Inspect the actual private GameReady GLB without modifying it.

Usage:
    python tools/audit_gameready_mesh.py game/assets/Octopus_GameReady_v5.glb

This determines what can actually be physics-driven from *the original*
surface: skinned vertices, number of primitives and possible open edges.
Watertight estimates are per primitive; UV seams and separate materials
can create false open boundaries.
"""
from __future__ import annotations
import collections
import json
import pathlib
import struct
import sys

COMPONENT_BYTES = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
COMPONENT_FMT = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
SHAPES = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}

def load_glb(path: pathlib.Path):
    raw = path.read_bytes()
    if len(raw) < 20:
        raise ValueError("Incomplete GLB header")
    magic, version, declared = struct.unpack_from("<4sII", raw)
    if magic != b"glTF" or version != 2 or declared != len(raw):
        raise ValueError("Not a valid glTF 2.0 GLB")
    offset, doc, data = 12, None, None
    while offset + 8 <= len(raw):
        length, kind = struct.unpack_from("<I4s", raw, offset)
        offset += 8
        chunk = raw[offset:offset + length]
        offset += length
        if kind == b"JSON":
            doc = json.loads(chunk)
        elif kind == b"BIN\x00":
            data = chunk
    if doc is None or data is None:
        raise ValueError("GLB must have JSON and BIN chunks")
    return doc, data

def read_accessor(doc, binary, index):
    a = doc["accessors"][index]
    if "sparse" in a:
        raise ValueError("Sparse accessors need a glTF importer; cannot audit this primitive")
    view = doc["bufferViews"][a["bufferView"]]
    n = SHAPES[a["type"]]
    byte_width = COMPONENT_BYTES[a["componentType"]]
    stride = view.get("byteStride", n * byte_width)
    offset = view.get("byteOffset", 0) + a.get("byteOffset", 0)
    fmt = "<" + COMPONENT_FMT[a["componentType"]] * n
    for i in range(a["count"]):
        yield struct.unpack_from(fmt, binary, offset + i * stride)

def describe(doc, binary):
    report = {"mesh_count": len(doc.get("meshes", [])), "nodes": len(doc.get("nodes", [])),
              "skins": len(doc.get("skins", [])), "primitives": [],
              "totals": {"vertices": 0, "triangles": 0, "bone_weighted_vertices": 0}}
    for mi, mesh in enumerate(doc.get("meshes", [])):
        for pi, primitive in enumerate(mesh.get("primitives", [])):
            attrs = primitive["attributes"]
            count = doc["accessors"][attrs["POSITION"]]["count"]
            joints = attrs.get("JOINTS_0")
            weights = attrs.get("WEIGHTS_0")
            texture = "TEXCOORD_0" in attrs
            index_id = primitive.get("indices")
            mode = primitive.get("mode", 4)
            faces = []
            if index_id is not None and mode == 4:
                indices = [int(v[0]) for v in read_accessor(doc, binary, index_id)]
                faces = [indices[i:i+3] for i in range(0, len(indices)-2, 3)]
            edges = collections.Counter()
            for face in faces:
                for i in range(3):
                    edges[tuple(sorted((face[i], face[(i+1) % 3])))] += 1
            boundaries = sum(1 for val in edges.values() if val == 1)
            nonmanifold = sum(1 for val in edges.values() if val > 2)
            entry = {"mesh": mi, "mesh_name": mesh.get("name",""),
                     "primitive": pi, "material": primitive.get("material"),
                     "vertices": count, "triangles": len(faces), "mode": mode,
                     "uv": texture, "skin_joints": joints is not None,
                     "skin_weights": weights is not None,
                     "boundary_edges_per_primitive": boundaries,
                     "nonmanifold_edges_per_primitive": nonmanifold}
            report["primitives"].append(entry)
            report["totals"]["vertices"] += count
            report["totals"]["triangles"] += len(faces)
            if joints is not None and weights is not None:
                report["totals"]["bone_weighted_vertices"] += count
    report["materials"] = [m.get("name", f"material_{i}")
                            for i,m in enumerate(doc.get("materials", []))]
    report["arm_bones"] = sum(bool(n.get("name", "").startswith("A") and
                               "_" in n.get("name", "")) for n in doc.get("nodes", []))
    return report

if __name__ == "__main__":
    target = pathlib.Path(sys.argv[1] if len(sys.argv)>1 else
                          "game/assets/Octopus_GameReady_v5.glb")
    if not target.is_file():
        sys.exit(f"Missing original GLB: {target} (local-only private asset)")
    doc, binary = load_glb(target)
    print(json.dumps(describe(doc, binary), indent=2, ensure_ascii=False))
