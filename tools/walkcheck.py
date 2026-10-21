#!/usr/bin/env python3
"""Walkability check for a map dump (tools/harness/buildmap.luau output).

    python3 tools/walkcheck.py map.json [out_prefix]

Rebuilds the world as columns of solid/water intervals on a 2-stud grid from
the recorded terrain fills (in order, later fills replace earlier ones) and
every collidable part, then flood-fills from the SpawnLocation (a map dump
holds one world, so one spawn: buildmap writes a file per world) the way a
character walks: step up at most STEP_UP studs, drop at most MAX_DROP, and
only stand where there is HEADROOM above. Water is not walkable.

Checks (exit 1 if any fail):
  * every zone's catch floor is reachable on foot from spawn
  * every sell area, research office, research camp and portal is reachable on foot from spawn
  * each catch floor is flat: >= 90% of its cells within 1.5 studs of the floor
  * each catch floor is open: >= 90% of its cells are standable
Writes out_prefix_walk.png (reachable cells green, catch floors outlined).
"""

import json
import math
import sys
from collections import deque

CELL = 2.0
STEP_UP = 2.4
MAX_DROP = 24.0
HEADROOM = 5.0
ROOT = 3.0  # HumanoidRootPart height above the ground
BORDER_BAND = 2.0
INF = float("inf")


def rot(cf):
    return [[cf[3], cf[4], cf[5]], [cf[6], cf[7], cf[8]], [cf[9], cf[10], cf[11]]]


def to_local_line(cf, x, z):
    """Local coords of the vertical line (x, t, z) are a + t*b."""
    r = rot(cf)
    px, pz = x - cf[0], z - cf[2]
    py0 = -cf[1]
    # local = R^T * (p - c)
    a = [r[0][i] * px + r[1][i] * py0 + r[2][i] * pz for i in range(3)]
    b = [r[1][i] for i in range(3)]
    return a, b


def clip_linear(lo, hi, a, b, bound):
    """Restrict t so that |a + t*b| <= bound."""
    if abs(b) < 1e-9:
        return (lo, hi) if abs(a) <= bound else (1, 0)
    t1, t2 = (-bound - a) / b, (bound - a) / b
    if t1 > t2:
        t1, t2 = t2, t1
    return max(lo, t1), min(hi, t2)


def clip_halfspace(lo, hi, a, b):
    """Restrict t so that a + t*b <= 0."""
    if abs(b) < 1e-9:
        return (lo, hi) if a <= 0 else (1, 0)
    t = -a / b
    return (lo, min(hi, t)) if b > 0 else (max(lo, t), hi)


def box_interval(cf, size, x, z):
    a, b = to_local_line(cf, x, z)
    lo, hi = -INF, INF
    for i in range(3):
        lo, hi = clip_linear(lo, hi, a[i], b[i], size[i] / 2)
        if lo > hi:
            return None
    return lo, hi


def wedge_interval(cf, size, x, z):
    iv = box_interval(cf, size, x, z)
    if not iv:
        return None
    a, b = to_local_line(cf, x, z)
    hy, hz = size[1] / 2, size[2] / 2
    # solid where y <= -hy + (hy/hz)*(z + hz)  (tall end at +Z)
    k = hy / hz if hz else 0
    ca = a[1] - (-hy + k * (a[2] + hz))
    cb = b[1] - k * b[2]
    lo, hi = clip_halfspace(iv[0], iv[1], ca, cb)
    return (lo, hi) if lo <= hi else None


def quad_interval(lo, hi, qa, qb, qc):
    """t where qa*t^2 + qb*t + qc <= 0, intersected with [lo, hi]."""
    if abs(qa) < 1e-9:
        if abs(qb) < 1e-9:
            return (lo, hi) if qc <= 0 else None
        t = -qc / qb
        lo, hi = (lo, min(hi, t)) if qb > 0 else (max(lo, t), hi)
        return (lo, hi) if lo <= hi else None
    disc = qb * qb - 4 * qa * qc
    if disc < 0:
        return None
    s = math.sqrt(disc)
    t1, t2 = (-qb - s) / (2 * qa), (-qb + s) / (2 * qa)
    lo, hi = max(lo, min(t1, t2)), min(hi, max(t1, t2))
    return (lo, hi) if lo <= hi else None


def cylinder_interval(cf, height, radius, x, z, axis):
    """Cylinder along local `axis` (1 = Y for terrain, 0 = X for parts)."""
    a, b = to_local_line(cf, x, z)
    lo, hi = clip_linear(-INF, INF, a[axis], b[axis], height / 2)
    if lo > hi:
        return None
    o = [i for i in range(3) if i != axis]
    qa = b[o[0]] ** 2 + b[o[1]] ** 2
    qb = 2 * (a[o[0]] * b[o[0]] + a[o[1]] * b[o[1]])
    qc = a[o[0]] ** 2 + a[o[1]] ** 2 - radius * radius
    return quad_interval(lo, hi, qa, qb, qc)


def ball_interval(center, radius, x, z):
    dx, dz = x - center[0], z - center[2]
    d2 = radius * radius - dx * dx - dz * dz
    if d2 < 0:
        return None
    s = math.sqrt(d2)
    return center[1] - s, center[1] + s


def bbox_xz(points):
    xs = [p[0] for p in points]
    zs = [p[2] for p in points]
    return min(xs), max(xs), min(zs), max(zs)


def corners(cf, size):
    r = rot(cf)
    out = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                l = (sx * size[0] / 2, sy * size[1] / 2, sz * size[2] / 2)
                out.append(tuple(cf[i] + sum(r[i][j] * l[j] for j in range(3)) for i in range(3)))
    return out


def subtract(intervals, lo, hi):
    out = []
    for (a, b, kind) in intervals:
        if b <= lo or a >= hi:
            out.append((a, b, kind))
        else:
            if a < lo:
                out.append((a, lo, kind))
            if b > hi:
                out.append((hi, b, kind))
    return out


def main():
    data = json.load(open(sys.argv[1]))
    prefix = sys.argv[2] if len(sys.argv) > 2 else None
    parts, terrain = data["parts"], data["terrain"]

    zones = [p for p in parts if ".Zones." in p["path"]]
    sells = [p for p in parts if p["name"] == "SellArea"]
    # research offices, camps and portals must be reachable like sell areas
    sites = [
        p
        for p in parts
        if p["name"] in ("ResearchOffice", "Portal") or ".ResearchCamps." in p["path"]
    ]
    spawns = [p for p in parts if p["class"] == "SpawnLocation"]
    if not spawns:
        print("FAIL: no SpawnLocation")
        sys.exit(1)

    # grid bounds: every part plus non-ocean terrain, with margin
    xs, zs = [], []
    for p in parts:
        if max(p["size"]) < 900:
            for c in corners(p["cframe"], p["size"]):
                xs.append(c[0])
                zs.append(c[2])
    minx, maxx = min(xs) - 40, max(xs) + 40
    minz, maxz = min(zs) - 40, max(zs) + 40
    nx, nz = int((maxx - minx) / CELL) + 1, int((maxz - minz) / CELL) + 1

    def cx(i):
        return minx + (i + 0.5) * CELL

    def cz(k):
        return minz + (k + 0.5) * CELL

    columns = [[[] for _ in range(nz)] for _ in range(nx)]

    def apply(xr, zr, interval_fn, kind):
        i0 = max(0, int((xr[0] - minx) / CELL))
        i1 = min(nx - 1, int((xr[1] - minx) / CELL) + 1)
        k0 = max(0, int((zr[0] - minz) / CELL))
        k1 = min(nz - 1, int((zr[1] - minz) / CELL) + 1)
        for i in range(i0, i1 + 1):
            x = cx(i)
            col = columns[i]
            for k in range(k0, k1 + 1):
                iv = interval_fn(x, cz(k))
                if iv and iv[1] > iv[0]:
                    lo, hi = iv
                    col[k] = subtract(col[k], lo, hi)
                    if kind != "air":
                        col[k].append((lo, hi, kind))

    # terrain, in order
    for op in terrain:
        kind = op.get("material", "")
        kind = "water" if kind == "Water" else ("air" if kind == "Air" else "solid")
        if op["kind"] == "Clear":
            continue
        if op["kind"] == "FillBlock":
            cf, size = op["cframe"], op["size"]
            x0, x1, z0, z1 = bbox_xz(corners(cf, size))
            apply((x0, x1), (z0, z1), lambda x, z, cf=cf, size=size: box_interval(cf, size, x, z), kind)
        elif op["kind"] == "FillWedge":
            cf, size = op["cframe"], op["size"]
            x0, x1, z0, z1 = bbox_xz(corners(cf, size))
            apply((x0, x1), (z0, z1), lambda x, z, cf=cf, size=size: wedge_interval(cf, size, x, z), kind)
        elif op["kind"] == "FillCylinder":
            cf, h, r = op["cframe"], op["height"], op["radius"]
            x0, x1, z0, z1 = bbox_xz(corners(cf, (2 * r, h, 2 * r)))
            apply((x0, x1), (z0, z1), lambda x, z, cf=cf, h=h, r=r: cylinder_interval(cf, h, r, x, z, 1), kind)
        elif op["kind"] == "FillBall":
            c, r = op["center"], op["radius"]
            apply((c[0] - r, c[0] + r), (c[2] - r, c[2] + r), lambda x, z, c=c, r=r: ball_interval(c, r, x, z), kind)

    # collidable parts are solid (they don't carve terrain, just add to it)
    for p in parts:
        if not p["canCollide"] or max(p["size"]) >= 900:
            continue
        cf, size = p["cframe"], p["size"]
        x0, x1, z0, z1 = bbox_xz(corners(cf, size))
        if p["shape"] == "Ball":
            c, r = cf[:3], size[0] / 2
            fn = lambda x, z, c=c, r=r: ball_interval(c, r, x, z)
        elif p["shape"] == "Cylinder":
            fn = lambda x, z, cf=cf, size=size: cylinder_interval(cf, size[0], min(size[1], size[2]) / 2, x, z, 0)
        elif p["shape"] == "Wedge":
            fn = lambda x, z, cf=cf, size=size: wedge_interval(cf, size, x, z)
        else:
            fn = lambda x, z, cf=cf, size=size: box_interval(cf, size, x, z)
        i0 = max(0, int((x0 - minx) / CELL))
        i1 = min(nx - 1, int((x1 - minx) / CELL) + 1)
        k0 = max(0, int((z0 - minz) / CELL))
        k1 = min(nz - 1, int((z1 - minz) / CELL) + 1)
        for i in range(i0, i1 + 1):
            for k in range(k0, k1 + 1):
                iv = fn(cx(i), cz(k))
                if iv and iv[1] > iv[0]:
                    columns[i][k].append((iv[0], iv[1], "solid"))

    # standable surfaces per cell: top of a solid with headroom, not underwater
    surfaces = [[[] for _ in range(nz)] for _ in range(nx)]
    for i in range(nx):
        for k in range(nz):
            col = sorted(columns[i][k])
            solids = [(a, b) for (a, b, kind) in col if kind == "solid"]
            waters = [(a, b) for (a, b, kind) in col if kind == "water"]
            # merge overlapping solids
            merged = []
            for a, b in sorted(solids):
                if merged and a <= merged[-1][1] + 0.05:
                    merged[-1] = (merged[-1][0], max(merged[-1][1], b))
                else:
                    merged.append((a, b))
            for idx, (a, b) in enumerate(merged):
                above = merged[idx + 1][0] if idx + 1 < len(merged) else INF
                if above - b < HEADROOM:
                    continue
                underwater = any(wa <= b + 0.5 <= wb for wa, wb in waters)
                if not underwater:
                    surfaces[i][k].append(b)

    def cell_of(x, z):
        return int((x - minx) / CELL), int((z - minz) / CELL)

    def nearest_surface(i, k, y):
        best = None
        for s in surfaces[i][k] if 0 <= i < nx and 0 <= k < nz else []:
            if best is None or abs(s - y) < abs(best - y):
                best = s
        return best

    # flood fill from spawn
    sp = spawns[0]
    si, sk = cell_of(sp["cframe"][0], sp["cframe"][2])
    start = nearest_surface(si, sk, sp["cframe"][1] + sp["size"][1] / 2)
    reached = {}
    if start is not None:
        queue = deque([(si, sk, start)])
        reached[(si, sk, round(start, 1))] = True
        while queue:
            i, k, h = queue.popleft()
            for di, dk in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
                ni, nk = i + di, k + dk
                if not (0 <= ni < nx and 0 <= nk < nz):
                    continue
                for s in surfaces[ni][nk]:
                    if s - h <= STEP_UP and h - s <= MAX_DROP:
                        key = (ni, nk, round(s, 1))
                        if key not in reached:
                            reached[key] = True
                            queue.append((ni, nk, s))
    reached_cells = {}
    for (i, k, s) in reached:
        reached_cells.setdefault((i, k), []).append(s)

    failures = []
    report = []

    def reachable_near(x, z, y, tolerance=3.0):
        i, k = cell_of(x, z)
        for di in range(-1, 2):
            for dk in range(-1, 2):
                for s in reached_cells.get((i + di, k + dk), []):
                    if abs(s - y) <= tolerance:
                        return True
        return False

    for zp in zones:
        cf, size = zp["cframe"], zp["size"]
        r = rot(cf)
        floor = cf[1] - size[1] / 2 + 1  # Builder puts the volume 1 stud below the floor
        hw, hd = size[0] / 2 - BORDER_BAND, size[2] / 2 - BORDER_BAND
        total = flat = open_ = reach = 0
        steps_x, steps_z = int(hw * 2 / CELL), int(hd * 2 / CELL)
        for a in range(steps_x):
            for b in range(steps_z):
                lx, lz = -hw + (a + 0.5) * CELL, -hd + (b + 0.5) * CELL
                x = cf[0] + r[0][0] * lx + r[0][2] * lz
                z = cf[2] + r[2][0] * lx + r[2][2] * lz
                i, k = cell_of(x, z)
                total += 1
                s = nearest_surface(i, k, floor)
                if s is not None:
                    open_ += 1
                    if abs(s - floor) <= 1.5:
                        flat += 1
                if reachable_near(x, z, floor, 1.6):
                    reach += 1
        name = zp["name"]
        flat_pct, open_pct, reach_pct = 100 * flat / total, 100 * open_ / total, 100 * reach / total
        report.append(f"{name}: floor y={floor:.1f}  flat {flat_pct:.0f}%  open {open_pct:.0f}%  reachable {reach_pct:.0f}%")
        if reach_pct < 50:
            failures.append(f"{name}: catch floor not reachable on foot from spawn ({reach_pct:.0f}%)")
        if flat_pct < 90:
            failures.append(f"{name}: catch floor not flat ({flat_pct:.0f}% within 1.5 studs of y={floor:.1f})")
        if open_pct < 90:
            failures.append(f"{name}: catch floor blocked ({open_pct:.0f}% standable)")

    for sa in sells:
        cf, size = sa["cframe"], sa["size"]
        bottom = cf[1] - size[1] / 2 + 1
        ok = reachable_near(cf[0], cf[2], bottom, 3.0)
        report.append(f"{sa['path']}: {'reachable' if ok else 'NOT reachable'} (pad top ~{bottom:.1f})")
        if not ok:
            failures.append(f"{sa['path']}: sell area not reachable on foot from spawn")

    for rs in sites:
        cf, size = rs["cframe"], rs["size"]
        bottom = cf[1] - size[1] / 2 + 1
        ok = reachable_near(cf[0], cf[2], bottom, 3.0)
        report.append(f"{rs['path']}: {'reachable' if ok else 'NOT reachable'} (pad top ~{bottom:.1f})")
        if not ok:
            kind = "portal" if rs["name"] == "Portal" else "research site"
            failures.append(f"{rs['path']}: {kind} not reachable on foot from spawn")

    reach_count = len(reached_cells)
    report.append(f"walkable cells reached from spawn: {reach_count} ({reach_count * CELL * CELL:.0f} sq studs)")
    for line in report:
        print(line)
    for f in failures:
        print("FAIL: " + f)

    if prefix:
        try:
            from PIL import Image, ImageDraw
        except ImportError:
            prefix = None
    if prefix:
        img = Image.new("RGB", (nx, nz), (25, 40, 70))
        px = img.load()
        for i in range(nx):
            for k in range(nz):
                if surfaces[i][k]:
                    h = max(surfaces[i][k])
                    g = max(40, min(200, int(80 + h * 3)))
                    px[i, k] = (g, g, g)
        for (i, k) in reached_cells:
            h = max(reached_cells[(i, k)])
            g = max(80, min(255, int(120 + h * 3)))
            px[i, k] = (40, g, 70)
        img = img.resize((nx * 3, nz * 3), Image.NEAREST)
        draw = ImageDraw.Draw(img)
        for zp in zones:
            pts = []
            cf, size = zp["cframe"], zp["size"]
            r = rot(cf)
            for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                lx, lz = sx * size[0] / 2, sz * size[2] / 2
                x = cf[0] + r[0][0] * lx + r[0][2] * lz
                z = cf[2] + r[2][0] * lx + r[2][2] * lz
                pts.append(((x - minx) / CELL * 3, (z - minz) / CELL * 3))
            draw.polygon(pts, outline=(255, 255, 255))
        for sa in sells:
            x, z = (sa["cframe"][0] - minx) / CELL * 3, (sa["cframe"][2] - minz) / CELL * 3
            draw.ellipse([x - 8, z - 8, x + 8, z + 8], outline=(255, 40, 200), width=3)
        x, z = (sp["cframe"][0] - minx) / CELL * 3, (sp["cframe"][2] - minz) / CELL * 3
        draw.ellipse([x - 8, z - 8, x + 8, z + 8], outline=(0, 255, 255), width=3)
        img.save(prefix + "_walk.png")
        print("wrote", prefix + "_walk.png")

    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
