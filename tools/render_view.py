#!/usr/bin/env python3
"""Draws the map from a player's point of view: a small perspective
renderer for the map.json files tools/harness/buildmap.luau writes, so
signs, portals and bridges can be reviewed without Studio.

Every visible part becomes triangles (blocks, wedges, cylinders, balls),
lit by a low sun and drawn with a depth buffer; sign text (SurfaceGuis) is
drawn onto its face, hidden wherever something stands in front of it.

  python3 tools/render_view.py map.json out.png --eye=X,Y,Z --at=X,Y,Z [--fov 70]
  python3 tools/render_view.py map.json outdir --signs [--fail-under 0.9]

(Write --eye=... with the = so a negative first number isn't read as a flag.)

--signs looks at every sign face from where a player would stand in front
of it (on the ground, as far back as the open ground goes before a wall or
a drop, straight on and 15 degrees to each side), writes the worst of those
views per sign and prints how much of each sign shows; with --fail-under it
exits 1 if any sign shows less than that fraction straight on. A fence post
in front of a sign's back costs about 10%; a sign facing a wall reads 0%.
Needs numpy and Pillow.
"""

import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SKY_TOP = np.array([0.42, 0.55, 0.78])
SKY_LOW = np.array([0.78, 0.84, 0.92])
SUN = np.array([-0.45, 0.8, 0.4])
SUN = SUN / np.linalg.norm(SUN)
NEAR = 0.3

# outward normal of each face, and the sign text's right and up axes on it
# (as SurfaceGuis draw them), in the part's own space
FACES = {
    "Front": ((0, 0, -1), (-1, 0, 0), (0, 1, 0)),
    "Back": ((0, 0, 1), (1, 0, 0), (0, 1, 0)),
    "Right": ((1, 0, 0), (0, 0, -1), (0, 1, 0)),
    "Left": ((-1, 0, 0), (0, 0, 1), (0, 1, 0)),
    "Top": ((0, 1, 0), (1, 0, 0), (0, 0, -1)),
    "Bottom": ((0, -1, 0), (1, 0, 0), (0, 0, 1)),
}


def frame(part):
    c = part["cframe"]
    pos = np.array(c[0:3], dtype=float)
    rot = np.array(c[3:12], dtype=float).reshape(3, 3)
    return pos, rot


# Geometry ------------------------------------------------------------------------


def _box(hx, hy, hz):
    v = np.array(
        [
            [-hx, -hy, -hz], [hx, -hy, -hz], [hx, hy, -hz], [-hx, hy, -hz],
            [-hx, -hy, hz], [hx, -hy, hz], [hx, hy, hz], [-hx, hy, hz],
        ]
    )
    quads = [
        ((0, 3, 2, 1), (0, 0, -1)),
        ((4, 5, 6, 7), (0, 0, 1)),
        ((0, 4, 7, 3), (-1, 0, 0)),
        ((1, 2, 6, 5), (1, 0, 0)),
        ((3, 7, 6, 2), (0, 1, 0)),
        ((0, 1, 5, 4), (0, -1, 0)),
    ]
    return v, quads


def _wedge(hx, hy, hz):
    # Roblox WedgePart: the slope runs from the top back edge (+Z) down to
    # the bottom front edge (-Z)
    v = np.array(
        [[-hx, -hy, -hz], [hx, -hy, -hz], [hx, -hy, hz], [-hx, -hy, hz], [hx, hy, hz], [-hx, hy, hz]]
    )
    slope = np.cross(v[1] - v[0], v[5] - v[0])
    n = slope / (np.linalg.norm(slope) or 1)
    if n[1] < 0:
        n = -n
    quads = [
        ((0, 1, 2, 3), (0, -1, 0)),
        ((3, 2, 4, 5), (0, 0, 1)),
        ((0, 5, 4, 1), tuple(n)),
        ((0, 3, 5), (-1, 0, 0)),
        ((1, 4, 2), (1, 0, 0)),
    ]
    return v, quads


def _cylinder(hx, r, segments=16):
    ring = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        ring.append((math.cos(a) * r, math.sin(a) * r))
    v = [[-hx, y, z] for y, z in ring] + [[hx, y, z] for y, z in ring]
    quads = []
    for i in range(segments):
        j = (i + 1) % segments
        a = 2 * math.pi * (i + 0.5) / segments
        quads.append(((i, j, segments + j, segments + i), (0, math.cos(a), math.sin(a))))
    quads.append((tuple(range(segments - 1, -1, -1)), (-1, 0, 0)))
    quads.append((tuple(range(segments, 2 * segments)), (1, 0, 0)))
    return np.array(v), quads


def _ball(r, rings=6, segments=10):
    v = []
    for i in range(rings + 1):
        phi = math.pi * i / rings
        for j in range(segments):
            theta = 2 * math.pi * j / segments
            v.append([r * math.sin(phi) * math.cos(theta), r * math.cos(phi), r * math.sin(phi) * math.sin(theta)])
    quads = []
    for i in range(rings):
        for j in range(segments):
            a = i * segments + j
            b = i * segments + (j + 1) % segments
            c = (i + 1) * segments + (j + 1) % segments
            d = (i + 1) * segments + j
            mid = (np.array(v[a]) + np.array(v[c])) / 2
            n = mid / (np.linalg.norm(mid) or 1)
            quads.append(((a, b, c, d), tuple(n)))
    return np.array(v), quads


def mesh(part):
    """World-space vertices and (vertex indices, world normal) faces."""
    sx, sy, sz = part["size"]
    shape = part.get("shape", "Block")
    if shape == "Cylinder":
        v, quads = _cylinder(sx / 2, min(sy, sz) / 2)
    elif shape == "Ball":
        v, quads = _ball(min(sx, sy, sz) / 2)
    elif shape in ("Wedge", "CornerWedge"):
        v, quads = _wedge(sx / 2, sy / 2, sz / 2)
    else:
        v, quads = _box(sx / 2, sy / 2, sz / 2)
    pos, rot = frame(part)
    world = v @ rot.T + pos
    faces = [(idx, rot @ np.array(n, dtype=float)) for idx, n in quads]
    return world, faces


# Camera ---------------------------------------------------------------------------


class Camera:
    def __init__(self, eye, at, fov, width, height):
        self.eye = np.array(eye, dtype=float)
        forward = np.array(at, dtype=float) - self.eye
        self.forward = forward / np.linalg.norm(forward)
        right = np.cross(self.forward, [0.0, 1.0, 0.0])
        if np.linalg.norm(right) < 1e-6:
            right = np.array([1.0, 0.0, 0.0])
        self.right = right / np.linalg.norm(right)
        self.up = np.cross(self.right, self.forward)
        self.w, self.h = width, height
        self.focal = (width / 2) / math.tan(math.radians(fov) / 2)

    def to_view(self, points):
        d = points - self.eye
        return np.stack([d @ self.right, d @ self.up, d @ self.forward], axis=-1)

    def project_view(self, v):
        """View-space points (z > 0) to screen x, y and 1/z."""
        iz = 1.0 / v[..., 2]
        x = self.w / 2 + v[..., 0] * iz * self.focal
        y = self.h / 2 - v[..., 1] * iz * self.focal
        return x, y, iz

    def visible_sphere(self, center, radius, far):
        v = self.to_view(center[None, :])[0]
        if v[2] < -radius or v[2] - radius > far:
            return False
        z = max(v[2], NEAR)
        limit_x = z * (self.w / 2) / self.focal + radius * 1.5
        limit_y = z * (self.h / 2) / self.focal + radius * 1.5
        return abs(v[0]) <= limit_x and abs(v[1]) <= limit_y


def clip_near(poly):
    """Clips a view-space polygon (list of xyz) to z >= NEAR."""
    out = []
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        ina, inb = a[2] >= NEAR, b[2] >= NEAR
        if ina:
            out.append(a)
        if ina != inb:
            t = (NEAR - a[2]) / (b[2] - a[2])
            out.append(a + (b - a) * t)
    return out


# Shading -------------------------------------------------------------------------


def shade(part, normal, depth):
    color = np.array(part["color"], dtype=float)
    material = part.get("material", "")
    if material == "Neon":
        lit = np.minimum(color * 1.15 + 0.08, 1.0)
    else:
        diffuse = max(0.0, float(normal @ SUN))
        sky = 0.5 + 0.5 * max(0.0, float(normal[1]))
        lit = color * (0.38 + 0.18 * sky + 0.5 * diffuse)
        if material == "Glass":
            lit = lit * 0.7 + 0.25
    haze = 1 - math.exp(-max(depth, 0) / 900)
    return np.clip(lit * (1 - haze) + SKY_LOW * haze, 0, 1)


# Rendering ------------------------------------------------------------------------


class Frame:
    def __init__(self, cam):
        self.cam = cam
        h, w = cam.h, cam.w
        rows = np.linspace(0, 1, h)[:, None, None]
        self.color = np.broadcast_to(SKY_TOP * (1 - rows) + SKY_LOW * rows, (h, w, 3)).copy()
        self.zbuf = np.zeros((h, w))  # 1/z, bigger is closer
        self.ids = np.full((h, w), -1, dtype=np.int32)

    def triangle(self, pts, rgb, pid, alpha=1.0):
        """Fills one screen triangle: pts are (x, y, 1/z)."""
        (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = pts
        w, h = self.cam.w, self.cam.h
        minx = max(int(math.floor(min(x0, x1, x2))), 0)
        maxx = min(int(math.ceil(max(x0, x1, x2))), w - 1)
        miny = max(int(math.floor(min(y0, y1, y2))), 0)
        maxy = min(int(math.ceil(max(y0, y1, y2))), h - 1)
        if minx > maxx or miny > maxy:
            return
        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(area) < 1e-9:
            return
        px, py = np.meshgrid(np.arange(minx, maxx + 1) + 0.5, np.arange(miny, maxy + 1) + 0.5)
        b0 = ((x1 - px) * (y2 - py) - (x2 - px) * (y1 - py)) / area
        b1 = ((x2 - px) * (y0 - py) - (x0 - px) * (y2 - py)) / area
        b2 = 1 - b0 - b1
        eps = -1e-4
        inside = (b0 >= eps) & (b1 >= eps) & (b2 >= eps)
        if not inside.any():
            return
        iz = b0 * z0 + b1 * z1 + b2 * z2
        zone = self.zbuf[miny : maxy + 1, minx : maxx + 1]
        front = inside & (iz > zone)
        if not front.any():
            return
        region = self.color[miny : maxy + 1, minx : maxx + 1]
        if alpha >= 1:
            zone[front] = iz[front]
            region[front] = rgb
            self.ids[miny : maxy + 1, minx : maxx + 1][front] = pid
        else:
            region[front] = region[front] * (1 - alpha) + np.array(rgb) * alpha

    def draw_part(self, part, pid, far):
        cam = self.cam
        pos, _ = frame(part)
        radius = 0.5 * float(np.linalg.norm(part["size"]))
        if not cam.visible_sphere(pos, radius, far):
            return
        verts, faces = mesh(part)
        view = cam.to_view(verts)
        alpha = 1.0 - float(part.get("transparency", 0))
        for idx, normal in faces:
            center = verts[list(idx)].mean(axis=0)
            if normal @ (cam.eye - center) <= 0:
                continue  # facing away
            poly = [view[i] for i in idx]
            if min(p[2] for p in poly) < NEAR:
                poly = clip_near(poly)
                if len(poly) < 3:
                    continue
            arr = np.array(poly)
            x, y, iz = cam.project_view(arr)
            rgb = shade(part, normal, float(arr[:, 2].mean()))
            pts = list(zip(x, y, iz))
            for k in range(1, len(pts) - 1):
                self.triangle((pts[0], pts[k], pts[k + 1]), rgb, pid, alpha)

    def draw_beam(self, beam):
        cam = self.cam
        a, b = np.array(beam["a"], dtype=float), np.array(beam["b"], dtype=float)
        va, vb = cam.to_view(np.stack([a, b]))
        if va[2] < NEAR and vb[2] < NEAR:
            return
        rgb = np.clip(np.array(beam.get("color", [1, 1, 1])) * 1.1, 0, 1)
        steps = 64
        for t in np.linspace(0, 1, steps):
            v = va + (vb - va) * t
            if v[2] < NEAR:
                continue
            x, y, iz = cam.project_view(v)
            xi, yi = int(x), int(y)
            if 0 <= xi < cam.w and 0 <= yi < cam.h and iz >= self.zbuf[yi, xi] * 0.98:
                r = max(1, min(3, int(beam.get("width", 0.3) * iz * cam.focal / 2)))
                self.color[max(yi - r // 2, 0) : yi + r // 2 + 1, max(xi - r // 2, 0) : xi + r // 2 + 1] = rgb


def homography(src, dst):
    """Coefficients for PIL's PERSPECTIVE transform: dst (output) -> src (input)."""
    rows, rhs = [], []
    for (x, y), (u, v) in zip(dst, src):
        rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        rows.append([0, 0, 0, x, y, 1, -v * x, -v * y])
        rhs += [u, v]
    return np.linalg.solve(np.array(rows, dtype=float), np.array(rhs, dtype=float))


def fit_font(draw, text, box_w, box_h):
    size = max(int(box_h * 0.9), 6)
    while size > 6:
        font = ImageFont.truetype(FONT, size)
        x0, y0, x1, y1 = draw.textbbox((0, 0), text, font=font, stroke_width=max(1, size // 12))
        if x1 - x0 <= box_w and y1 - y0 <= box_h:
            return font
        size = int(size * 0.9)
    return ImageFont.truetype(FONT, 6)


def text_image(lines, width_studs, height_studs, board):
    scale = 24
    tw = max(16, min(int(width_studs * scale), 900))
    th = max(8, min(int(height_studs * scale), 600))
    img = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    title = lines[0] if lines else ""
    subtitle = lines[1] if len(lines) > 1 else None
    boxes = [(title, 0.06, 0.56 if subtitle else 0.88)]
    if subtitle:
        boxes.append((subtitle, 0.64, 0.3))
    light = sum(board) / 3 < 0.55
    fill = (255, 255, 255, 255) if light else (20, 20, 30, 255)
    stroke = (15, 15, 25, 255) if light else (255, 255, 255, 255)
    for text, top, height in boxes:
        text = text.encode("ascii", "replace").decode().replace("?", "") or text
        box_w, box_h = tw * 0.9, th * height
        font = fit_font(draw, text, box_w, box_h)
        x0, y0, x1, y1 = draw.textbbox((0, 0), text, font=font)
        x = (tw - (x1 - x0)) / 2 - x0
        y = th * top + (box_h - (y1 - y0)) / 2 - y0
        draw.text((x, y), text, font=font, fill=fill, stroke_width=max(1, font.size // 12), stroke_fill=stroke)
    return img


def face_quad(part, face):
    """World corners (top-left, top-right, bottom-right, bottom-left), the
    face normal and its size in studs, for a sign face."""
    normal_l, right_l, up_l = (np.array(a, dtype=float) for a in FACES[face])
    size = np.array(part["size"], dtype=float)
    pos, rot = frame(part)
    center = pos + rot @ (normal_l * size / 2)
    width = float(np.abs(right_l) @ size)
    height = float(np.abs(up_l) @ size)
    right, up = rot @ right_l, rot @ up_l
    corners = [
        center - right * width / 2 + up * height / 2,
        center + right * width / 2 + up * height / 2,
        center + right * width / 2 - up * height / 2,
        center - right * width / 2 - up * height / 2,
    ]
    return np.array(corners), rot @ normal_l, center, width, height


def draw_texts(fr, parts):
    cam = fr.cam
    for pid, part in enumerate(parts):
        for entry in part.get("texts") or []:
            corners, normal, center, width, height = face_quad(part, entry["face"])
            if normal @ (cam.eye - center) <= 0:
                continue
            view = cam.to_view(corners)
            if (view[:, 2] < NEAR).any():
                continue
            x, y, _ = cam.project_view(view)
            dst = list(zip(x, y))
            minx, maxx = max(int(min(x)), 0), min(int(max(x)) + 1, cam.w)
            miny, maxy = max(int(min(y)), 0), min(int(max(y)) + 1, cam.h)
            if maxx - minx < 2 or maxy - miny < 2:
                continue
            img = text_image(entry["lines"], width, height, part["color"])
            tw, th = img.size
            coeffs = homography([(0, 0), (tw, 0), (tw, th), (0, th)], dst)
            warped = img.transform((cam.w, cam.h), Image.PERSPECTIVE, tuple(coeffs), Image.BILINEAR)
            a = np.asarray(warped, dtype=float)[miny:maxy, minx:maxx] / 255.0
            mask = (fr.ids[miny:maxy, minx:maxx] == pid)[..., None]
            alpha = a[..., 3:4] * mask
            region = fr.color[miny:maxy, minx:maxx]
            region[:] = region * (1 - alpha) + a[..., :3] * alpha


def render(world, eye, at, fov=70, size=(1280, 800), far=1500, label=None):
    cam = Camera(eye, at, fov, *size)
    fr = Frame(cam)
    parts = world["parts"]
    clear = []
    for pid, part in enumerate(parts):
        t = float(part.get("transparency", 0))
        if t >= 0.95:
            continue
        if t > 0.02:
            clear.append((pid, part))
        else:
            fr.draw_part(part, pid, far)
    for beam in world.get("beams", []):
        fr.draw_beam(beam)
    draw_texts(fr, parts)
    for pid, part in sorted(clear, key=lambda item: -float(np.linalg.norm(frame(item[1])[0] - cam.eye))):
        fr.draw_part(part, pid, far)
    img = Image.fromarray((np.clip(fr.color, 0, 1) * 255).astype(np.uint8))
    if label:
        ImageDraw.Draw(img).text((8, 6), label, fill=(255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0))
    return img, fr


# Where a player can stand -------------------------------------------------------


class Solids:
    """The visible solid parts as oriented boxes, for "is this point inside
    something?" and "where's the ground under here?"."""

    def __init__(self, parts, collide_only=False):
        keep = [
            p
            for p in parts
            if float(p.get("transparency", 0)) < 0.5 and (p.get("canCollide", True) or not collide_only)
        ]
        self.pos = np.array([frame(p)[0] for p in keep]).reshape(-1, 3)
        self.rot = np.array([frame(p)[1] for p in keep]).reshape(-1, 3, 3)
        self.half = np.array([p["size"] for p in keep], dtype=float).reshape(-1, 3) / 2
        self.reach = np.linalg.norm(self.half, axis=1)
        shapes = [p.get("shape", "Block") for p in keep]
        self.ball = np.array([s == "Ball" for s in shapes], dtype=bool)
        self.cyl = np.array([s == "Cylinder" for s in shapes], dtype=bool)
        self.wedge = np.array([s == "Wedge" for s in shapes], dtype=bool)

    def inside(self, point, margin=0.0):
        near = np.linalg.norm(self.pos - point, axis=1) <= self.reach + margin
        if not near.any():
            return False
        local = np.einsum("nji,nj->ni", self.rot[near], point - self.pos[near])
        half = self.half[near] + margin
        box = (np.abs(local) <= half).all(axis=1)
        # balls and cylinders (round along X) are smaller than their boxes
        radius = np.minimum(half[:, 1], half[:, 2])
        ball = np.linalg.norm(local, axis=1) <= np.minimum(radius, half[:, 0])
        cyl = (np.abs(local[:, 0]) <= half[:, 0]) & (np.hypot(local[:, 1], local[:, 2]) <= radius)
        # a wedge is full height at +Z and slopes down to nothing at -Z
        wedge = box & (half[:, 2] * local[:, 1] - half[:, 1] * local[:, 2] <= 0)
        hit = np.where(self.ball[near], ball, np.where(self.cyl[near], cyl, np.where(self.wedge[near], wedge, box)))
        return bool(hit.any())

    def ground(self, x, z, top):
        """Highest top surface under (x, z) and below `top`, or None."""
        flat = np.linalg.norm((self.pos - np.array([x, 0.0, z]))[:, [0, 2]], axis=1) <= self.reach
        best = None
        origin = np.array([x, top, z])
        down = np.array([0.0, -1.0, 0.0])
        for pos, rot, half, wedge in zip(self.pos[flat], self.rot[flat], self.half[flat], self.wedge[flat]):
            o = rot.T @ (origin - pos)
            d = rot.T @ down
            tmin, tmax = -1e9, 1e9
            hit = True
            for k in range(3):
                if abs(d[k]) < 1e-9:
                    if abs(o[k]) > half[k]:
                        hit = False
                        break
                else:
                    t1, t2 = (-half[k] - o[k]) / d[k], (half[k] - o[k]) / d[k]
                    tmin, tmax = max(tmin, min(t1, t2)), min(tmax, max(t1, t2))
            if hit and wedge:
                # under the slope: hz*y - hy*z <= 0 along the ray
                a = half[2] * o[1] - half[1] * o[2]
                b = half[2] * d[1] - half[1] * d[2]
                if abs(b) < 1e-9:
                    hit = a <= 0
                elif b > 0:
                    tmax = min(tmax, -a / b)
                else:
                    tmin = max(tmin, -a / b)
            if hit and tmin <= tmax and tmax >= 0:
                y = top - max(tmin, 0)
                if best is None or y > best:
                    best = y
        return best


# Sign check -----------------------------------------------------------------------


def sign_views(solids, walls, parts, pid, entry):
    """Where players look at this sign face from: straight in front of it
    and 15 degrees to each side, as far back as 1.6 sign widths (at least
    16 studs), stopping before anything solid at the sign's height and at
    the edge of a drop (a cliff or the end of a deck), standing on the
    ground there (or at the sign's height over the void). Returns (eye,
    target, open distance) per view."""
    part = parts[pid]
    corners, normal, center, width, height = face_quad(part, entry["face"])
    flat = np.array([normal[0], 0.0, normal[2]])
    if np.linalg.norm(flat) < 0.3:
        return []  # lettering on a top face: read from above, skip
    flat /= np.linalg.norm(flat)
    distance = max(16.0, 1.6 * width)
    reach = center[1] + 1  # ground higher than this isn't somewhere to stand under it
    views = []
    for yaw in (0, -15, 15):
        a = math.radians(yaw)
        d = np.array([flat[0] * math.cos(a) - flat[2] * math.sin(a), 0, flat[0] * math.sin(a) + flat[2] * math.cos(a)])
        open_to = distance
        stand = None  # the furthest spot so far with ground to stand on
        last = None
        step = 1.0
        while step <= distance:
            spot = center + d * step
            if walls.inside(spot):
                open_to = step - 1.0
                break
            ground = solids.ground(spot[0], spot[2], reach)
            if ground is not None and (last is None or ground > last - 4):
                if stand is None or step - stand[0] <= 1.5:
                    stand = (step, ground)
                last = ground
            elif stand is not None:
                break  # the ground drops away: stop at the edge
            step += 1.0
        if stand is not None and stand[0] >= 3:
            back, ground = stand
            spot = center + d * back
            eye = np.array([spot[0], min(ground + 5.5, center[1] + 6), spot[2]])
            if walls.inside(eye):
                eye = np.array([spot[0], center[1], spot[2]])
        else:
            back = max(min(distance, open_to), 1.0)
            spot = center + d * back
            eye = np.array([spot[0], center[1], spot[2]])
        views.append((eye, center, open_to))
    return views


def visible_fraction(fr, part_id, corners):
    cam = fr.cam
    view = cam.to_view(corners)
    if (view[:, 2] < NEAR).any():
        return 0.0
    x, y, _ = cam.project_view(view)
    mask = Image.new("L", (cam.w, cam.h), 0)
    ImageDraw.Draw(mask).polygon(list(zip(x, y)), fill=255)
    m = np.asarray(mask) > 0
    total = m.sum()
    if total == 0:
        return 0.0
    return float((m & (fr.ids == part_id)).sum()) / float(total)


def check_signs(world, outdir, fail_under):
    os.makedirs(outdir, exist_ok=True)
    parts = world["parts"]
    solids = Solids(parts, collide_only=True)
    walls = Solids(parts)
    report = []
    index = 0
    for pid, part in enumerate(parts):
        for entry in part.get("texts") or []:
            views = sign_views(solids, walls, parts, pid, entry)
            if not views:
                continue
            corners, _, center, _, _ = face_quad(part, entry["face"])
            fractions = []
            images = []
            for eye, at, open_to in views:
                far = float(np.linalg.norm(at - eye)) + 4
                img, fr = render(world, eye, at, fov=60, size=(480, 300), far=far)
                # a sign you can't stand back from (a wall 3 studs in front) is blocked
                fraction = visible_fraction(fr, pid, corners) if open_to >= 3 else 0.0
                fractions.append(fraction)
                images.append(img)
            # the straight-on view, unless a side view is much worse
            worst = int(np.argmin(fractions))
            worst_img = images[worst] if fractions[0] - fractions[worst] > 0.3 else images[0]
            title = (entry["lines"] or ["?"])[0]
            shown = min(fractions)
            index += 1
            name = f"{index:02d}_{''.join(ch if ch.isalnum() else '_' for ch in title)[:28]}_{entry['face']}.png"
            label = f"{title} ({entry['face']}): {shown * 100:.0f}% shows (straight on {fractions[0] * 100:.0f}%)"
            ImageDraw.Draw(worst_img).text((6, 4), label, fill=(255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0))
            worst_img.save(os.path.join(outdir, name))
            report.append((shown, fractions, title, entry["face"], part["path"], name))
    report.sort(key=lambda item: item[1][0])
    bad = 0
    for shown, fractions, title, face, path, name in report:
        flag = "BLOCKED" if fractions[0] < fail_under else ("side" if shown < fail_under else "ok")
        if fractions[0] < fail_under:
            bad += 1
        print(
            f"{flag:8s} {shown * 100:5.1f}%  (on {fractions[0] * 100:.0f}%, left {fractions[1] * 100:.0f}%, right {fractions[2] * 100:.0f}%)  "
            f"{title!r} [{face}] {path}  -> {name}"
        )
    print(f"{len(report)} sign faces, {bad} under {fail_under * 100:.0f}% straight on")
    return bad


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("map")
    parser.add_argument("out")
    parser.add_argument("--eye")
    parser.add_argument("--at")
    parser.add_argument("--fov", type=float, default=70)
    parser.add_argument("--size", default="1280x800")
    parser.add_argument("--signs", action="store_true")
    parser.add_argument("--fail-under", type=float, default=0.0)
    args = parser.parse_args()
    with open(args.map) as f:
        world = json.load(f)
    if args.signs:
        bad = check_signs(world, args.out, args.fail_under)
        sys.exit(1 if bad and args.fail_under > 0 else 0)
    eye = [float(v) for v in args.eye.split(",")]
    at = [float(v) for v in args.at.split(",")]
    w, h = (int(v) for v in args.size.split("x"))
    img, _ = render(world, eye, at, args.fov, (w, h), label=os.path.basename(args.out))
    img.save(args.out)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
