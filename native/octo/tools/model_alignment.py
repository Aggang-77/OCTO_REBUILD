"""Measure rest GameReady arm/sucker vertices against the C++ arm collision tubes.

This evaluates model-space positions and the demo's static scale/yaw. It does
not substitute for a deformed, skinned vertex-to-collider measurement.
"""
import json
import math
import struct
import sys
import numpy as np

SCALE = 1.35 / 2.3
YAW = -math.pi / 8


def glb(path):
    with open(path, "rb") as stream:
        magic, version, total = struct.unpack("<4sII", stream.read(12))
        assert magic == b"glTF" and version == 2
        size, kind = struct.unpack("<I4s", stream.read(8))
        assert kind == b"JSON"
        doc = json.loads(stream.read(size))
        size, kind = struct.unpack("<I4s", stream.read(8))
        assert kind == b"BIN\0"
        data = stream.read(size)
    return doc, data


def accessor(doc, data, index):
    item = doc["accessors"][index]
    view = doc["bufferViews"][item["bufferView"]]
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[item["type"]]
    dtype = {5126: "<f4", 5123: "<u2", 5125: "<u4", 5121: "u1"}[item["componentType"]]
    stride = view.get("byteStride", np.dtype(dtype).itemsize * components)
    start = view.get("byteOffset", 0) + item.get("byteOffset", 0)
    return np.ndarray((item["count"], components), dtype=dtype, buffer=data,
                      offset=start, strides=(stride, np.dtype(dtype).itemsize)).astype(float)


def mesh_vertices(doc, data, mesh_index):
    return np.concatenate([accessor(doc, data, primitive["attributes"]["POSITION"])
                           for primitive in doc["meshes"][mesh_index]["primitives"]])


def rest_bones(doc):
    nodes = doc["nodes"]
    parents = {}
    for parent, node in enumerate(nodes):
        for child in node.get("children", []):
            parents[child] = parent
    cache = {}

    def matrix(index):
        if index in cache:
            return cache[index]
        node = nodes[index]
        if "matrix" in node:
            local = np.asarray(node["matrix"], float).reshape((4, 4), order="F")
        else:
            x, y, z, w = node.get("rotation", [0, 0, 0, 1])
            local = np.eye(4)
            local[:3, :3] = np.array([
                [1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]]) @ np.diag(node.get("scale", [1, 1, 1]))
            local[:3, 3] = node.get("translation", [0, 0, 0])
        cache[index] = matrix(parents[index]) @ local if index in parents else local
        return cache[index]

    result = {}
    for index, node in enumerate(nodes):
        name = node.get("name", "")
        if name.startswith("A") and len(name) == 5 and name[2] == "_" and name[3:].isdigit():
            result[name] = world(matrix(index)[:3, 3][None, :])[0]
    return result


def nearest_polyline(points, centers):
    best = np.full(len(points), np.inf)
    progress = np.zeros(len(points))
    lengths = np.linalg.norm(np.diff(centers, axis=0), axis=1)
    cumulative = np.r_[0, np.cumsum(lengths)]
    for j, (a, b) in enumerate(zip(centers[:-1], centers[1:])):
        direction = b - a
        t = np.clip((points-a) @ direction / np.dot(direction, direction), 0, 1)
        radius = np.linalg.norm(points - (a + t[:, None]*direction), axis=1)
        selected = radius < best
        best[selected] = radius[selected]
        progress[selected] = (cumulative[j] + lengths[j]*t[selected]) / cumulative[-1]
    return best, progress, cumulative[-1]


def world(points):
    # Godot model offset is (0,.15,.1) in imported model coordinates.
    points = (points - np.array([0, .15, .1])) * SCALE
    c, s = math.cos(YAW), math.sin(YAW)
    return points @ np.array([[c, 0, -s], [0, 1, 0], [s, 0, c]])


def tube_metrics(points, arm):
    angle = arm * math.pi / 4
    direction = np.array([math.sin(angle), 0, math.cos(angle)])
    axial = points @ direction
    u = np.clip((axial - .2) / .9, 0, 1)
    closest = np.outer(.2 + .9 * u, direction)
    transverse = np.linalg.norm(points - closest, axis=1)
    radius = .036 * (1 - .8 * u)
    return axial, transverse, radius


def summarize(label, points, arm):
    axial, transverse, radius = tube_metrics(points, arm)
    selected = (axial >= .2) & (axial <= 1.1)
    error = np.abs(transverse[selected] - radius[selected])
    print(f"{label} arm={arm} vertices={len(points)} axial_vertices={selected.sum()} "
          f"surface_error_p50_m={np.percentile(error, 50):.4f} "
          f"p95_m={np.percentile(error, 95):.4f} "
          f"max_m={error.max():.4f} radial_p50_m={np.median(transverse[selected]):.4f}")


def main():
    doc, data = glb(sys.argv[1])
    bones = rest_bones(doc)
    suckers = [world(mesh_vertices(doc, data, arm)) for arm in range(8)]
    skin_parts = []
    arm_parts = []
    joints = doc["skins"][0]["joints"]
    for primitive in doc["meshes"][15]["primitives"]:
        attrs = primitive["attributes"]
        points = world(accessor(doc, data, attrs["POSITION"]))
        indices = accessor(doc, data, attrs["JOINTS_0"]).astype(int)
        weights = accessor(doc, data, attrs["WEIGHTS_0"])
        dominant = indices[np.arange(len(points)), weights.argmax(axis=1)]
        labels = np.array([doc["nodes"][joints[index]]["name"] for index in dominant])
        skin_parts.append(points)
        arm_parts.append(np.array([int(label[1]) if label.startswith("A") and
                                   len(label) == 5 and label[2] == "_" else -1
                                   for label in labels]))
    skin_points = np.concatenate(skin_parts)
    skin_arms = np.concatenate(arm_parts)
    for art, points in enumerate(suckers):
        # The Godot renderer maps physical arm k to art arm (7-k)%8.
        physical = (7 - art) % 8
        summarize(f"suckers_art_{art}", points, physical)
        centers = np.array([bones[f"A{art}_{j:02d}"] for j in range(24)])
        radial, u, length = nearest_polyline(points, centers)
        expected = .036 * (1-.8*u)
        print(f"rest_bone_art_{art} length_m={length:.4f} "
              f"suckers_radial_p50_m={np.median(radial):.4f} "
              f"p95_m={np.percentile(radial,95):.4f} "
              f"outside_physics_p95_m={np.percentile(np.maximum(radial-expected,0),95):.4f}")
        skin_arm = skin_points[skin_arms == art]
        skin_radial, skin_u, _ = nearest_polyline(skin_arm, centers)
        skin_expected = .036 * (1-.8*skin_u)
        print(f"rest_skin_art_{art} vertices={len(skin_arm)} "
              f"radial_p50_m={np.median(skin_radial):.4f} "
              f"radial_p95_m={np.percentile(skin_radial,95):.4f} "
              f"surface_error_p95_m={np.percentile(np.abs(skin_radial-skin_expected),95):.4f}")
    skin = world(mesh_vertices(doc, data, 15))
    arm_region = skin[np.linalg.norm(skin[:, [0, 2]], axis=1) > .22]
    assignment = np.argmin(np.stack([tube_metrics(arm_region, arm)[1]
                                      for arm in range(8)], axis=1), axis=1)
    for arm in range(8):
        summarize("skin", arm_region[assignment == arm], arm)


if __name__ == "__main__":
    main()
