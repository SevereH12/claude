#!/usr/bin/env python3
"""Finds flicker (z-fighting) in a map dump from tools/harness/buildmap.luau.

Two visible parts whose top faces lie on the same plane and overlap flicker
in Studio when their colours or materials differ: the renderer can't decide
which surface is in front. This checks every pair of level top faces.

    python3 tools/flickercheck.py map.json

Exits 1 and lists the pairs if it finds any.
"""

import json
import math
import sys

HEIGHT_TOLERANCE = 0.01  # tops closer than this count as the same plane
MIN_OVERLAP = 0.05  # studs of overlap needed (touching edges don't flicker)


def top_face(part):
    """(y, corners in x/z) of a level upward-facing top face, or None."""
    cf, size, shape = part["cframe"], part["size"], part["shape"]
    r = cf[3:12]  # row-major rotation
    pos = cf[:3]
    if shape == "Block":
        # the local axis pointing (nearly) straight up gives the top face
        for axis in range(3):
            up = r[3 + axis]  # world Y component of local axis `axis`
            if abs(abs(up) - 1) < 1e-4:
                break
        else:
            return None
        sign = 1 if up > 0 else -1
        others = [a for a in range(3) if a != axis]
        y = pos[1] + sign * size[axis] / 2
        corners = []
        for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            local = [0.0, 0.0, 0.0]
            local[axis] = sign * size[axis] / 2
            local[others[0]] = su * size[others[0]] / 2
            local[others[1]] = sv * size[others[1]] / 2
            x = pos[0] + r[0] * local[0] + r[1] * local[1] + r[2] * local[2]
            z = pos[2] + r[6] * local[0] + r[7] * local[1] + r[8] * local[2]
            corners.append((x, z))
        return y, corners
    if shape == "Cylinder":
        # cylinders run along local X; only upright ones have a level top
        up = r[3]
        if abs(abs(up) - 1) > 1e-4:
            return None
        y = pos[1] + (1 if up > 0 else -1) * size[0] / 2
        radius = min(size[1], size[2]) / 2
        # the inscribed octagon: never claims area the disc doesn't cover
        corners = [
            (pos[0] + radius * math.cos(a), pos[2] + radius * math.sin(a))
            for a in (i * math.pi / 4 for i in range(8))
        ]
        return y, corners
    return None


def project(points, axis):
    values = [p[0] * axis[0] + p[1] * axis[1] for p in points]
    return min(values), max(values)


def overlap(a, b):
    """Smallest overlap depth of two convex polygons (<= 0: apart)."""
    depth = math.inf
    for poly in (a, b):
        for i in range(len(poly)):
            p, q = poly[i], poly[(i + 1) % len(poly)]
            edge = (q[0] - p[0], q[1] - p[1])
            length = math.hypot(*edge)
            if length < 1e-9:
                continue
            axis = (-edge[1] / length, edge[0] / length)
            a_lo, a_hi = project(a, axis)
            b_lo, b_hi = project(b, axis)
            depth = min(depth, min(a_hi, b_hi) - max(a_lo, b_lo))
            if depth <= 0:
                return depth
    return depth


def contains(part, point):
    """Is `point` inside this (opaque) part's volume?"""
    cf, size, shape = part["cframe"], part["size"], part["shape"]
    r = cf[3:12]
    d = [point[i] - cf[i] for i in range(3)]
    # world -> local: multiply by the transpose of the rotation
    local = [
        r[0] * d[0] + r[3] * d[1] + r[6] * d[2],
        r[1] * d[0] + r[4] * d[1] + r[7] * d[2],
        r[2] * d[0] + r[5] * d[1] + r[8] * d[2],
    ]
    half = [s / 2 for s in size]
    if any(abs(local[i]) > half[i] for i in range(3)):
        return False
    if shape == "Cylinder":
        radius = min(half[1], half[2])
        return local[1] ** 2 + local[2] ** 2 <= radius * radius
    if shape == "Ball":
        return sum(v * v for v in local) <= half[0] * half[0]
    if shape == "Wedge":
        # solid below the slope from (y=-hy, z=-hz) up to (y=+hy, z=+hz)
        return local[1] <= -half[1] + (half[1] / half[2]) * (local[2] + half[2]) if half[2] else True
    return shape == "Block"


def inside_polygon(point, poly):
    sign = 0
    for i in range(len(poly)):
        p, q = poly[i], poly[(i + 1) % len(poly)]
        cross = (q[0] - p[0]) * (point[1] - p[1]) - (q[1] - p[1]) * (point[0] - p[0])
        if abs(cross) < 1e-9:
            continue
        if sign == 0:
            sign = 1 if cross > 0 else -1
        elif (cross > 0) != (sign > 0):
            return False
    return True


def visible_overlap(y, a, b, solids):
    """Is some of the overlap of polygons a and b at height y uncovered?"""
    xs = [p[0] for p in a + b]
    zs = [p[1] for p in a + b]
    lo_x = max(min(p[0] for p in a), min(p[0] for p in b))
    hi_x = min(max(p[0] for p in a), max(p[0] for p in b))
    lo_z = max(min(p[1] for p in a), min(p[1] for p in b))
    hi_z = min(max(p[1] for p in a), max(p[1] for p in b))
    steps = 6
    for i in range(steps + 1):
        for k in range(steps + 1):
            x = lo_x + (hi_x - lo_x) * (i + 0.5) / (steps + 1)
            z = lo_z + (hi_z - lo_z) * (k + 0.5) / (steps + 1)
            if not (inside_polygon((x, z), a) and inside_polygon((x, z), b)):
                continue
            above = (x, y + 0.05, z)
            if not any(contains(s, above) for s in solids if s["_box"][0] <= x <= s["_box"][1] and s["_box"][2] <= z <= s["_box"][3]):
                return True
    return False


def looks_same(p, q):
    same_color = all(abs(x - y) < 1 / 512 for x, y in zip(p["color"], q["color"]))
    return same_color and p.get("material") == q.get("material")


def describe(part):
    size = "x".join(f"{v:g}" for v in (round(s, 2) for s in part["size"]))
    path = part["path"].removeprefix("Workspace.Map.")
    return f"{path} ({part['shape']} {size} {part.get('material', '?')})"


def main():
    data = json.load(open(sys.argv[1]))
    faces = []
    for part in data["parts"]:
        if part["transparency"] >= 0.98 or "color" not in part:
            continue
        face = top_face(part)
        if face:
            y, corners = face
            xs = [c[0] for c in corners]
            zs = [c[1] for c in corners]
            faces.append((y, (min(xs), max(xs), min(zs), max(zs)), corners, part))
    faces.sort(key=lambda f: f[0])

    # opaque parts that can hide a face lying under them
    solids = []
    for part in data["parts"]:
        if part["transparency"] > 0.05 or max(part["size"]) >= 2000:
            continue
        cf, size = part["cframe"], part["size"]
        reach = math.sqrt(sum(v * v for v in size)) / 2
        part["_box"] = (cf[0] - reach, cf[0] + reach, cf[2] - reach, cf[2] + reach)
        solids.append(part)

    problems = []
    for i, (y, box, corners, part) in enumerate(faces):
        for j in range(i + 1, len(faces)):
            y2, box2, corners2, part2 = faces[j]
            if y2 - y > HEIGHT_TOLERANCE:
                break
            if box[1] < box2[0] or box2[1] < box[0] or box[3] < box2[2] or box2[3] < box[2]:
                continue
            if looks_same(part, part2):
                continue
            if overlap(corners, corners2) > MIN_OVERLAP and visible_overlap(
                y, corners, corners2, solids
            ):
                problems.append((y, part, part2, part["cframe"][:3]))

    for y, a, b, at in problems[:40]:
        print(f"FLICKER y={y:.2f} near ({at[0]:.0f}, {at[2]:.0f}): {describe(a)} / {describe(b)}")
    if problems:
        print(f"FAIL: {len(problems)} pairs of overlapping same-height tops with different looks")
        sys.exit(1)
    print("no flicker: no overlapping same-height tops with different looks")


if __name__ == "__main__":
    main()
