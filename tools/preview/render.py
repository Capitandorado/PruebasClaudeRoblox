#!/usr/bin/env python3
"""Approximate preview renders of VOID FACTORY's procedural models.

This is NOT Roblox's renderer: it ray-traces the exported parts (blocks, wedges, balls,
cylinders) with simple lighting so the shapes, colours and layout can be reviewed without
Roblox Studio. Neon parts are drawn emissive; glass/forcefield parts are translucent.

    lune run tools/preview/export.luau build/preview.json
    python3 tools/preview/render.py build/preview.json docs/images
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

LIGHT = np.array([-0.45, 0.8, -0.35])
LIGHT /= np.linalg.norm(LIGHT)
RARITY_COLORS = {
    "Common": (176, 190, 204), "Uncommon": (96, 224, 128), "Rare": (64, 160, 255),
    "Epic": (180, 96, 255), "Legendary": (255, 186, 48), "Mythic": (255, 70, 120),
    "Divine": (255, 246, 180), "Celestial": (110, 240, 255), "Void": (150, 70, 255),
    "Secret": (255, 255, 255), "Gold": (255, 205, 60), "Neon": (80, 255, 240),
    "Rainbow": (255, 120, 220), "Corrupted": (200, 20, 50),
}


def rotation(cf):
    return np.array(cf[3:12], dtype=float).reshape(3, 3)


def look_at(eye, target):
    eye, target = np.array(eye, float), np.array(target, float)
    forward = target - eye
    forward /= np.linalg.norm(forward)
    right = np.cross(forward, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, forward)
    return eye, right, up, forward


def background(h, w, seed=3):
    y = np.linspace(0, 1, h)[:, None, None]
    top = np.array([0.05, 0.03, 0.12])
    bottom = np.array([0.16, 0.08, 0.28])
    img = top * (1 - y) + bottom * y
    img = np.repeat(img, w, axis=1)
    rng = np.random.default_rng(seed)
    stars = rng.random((h, w)) > 0.9985
    img[stars] = 0.85
    return img


def intersect_convex(o, d, planes):
    """planes: list of (normal, c) with inside n.p <= c. o: (3,), d: (N,3)."""
    n_rays = d.shape[0]
    t_enter = np.full(n_rays, -np.inf)
    t_exit = np.full(n_rays, np.inf)
    normal_index = np.zeros(n_rays, dtype=int)
    miss = np.zeros(n_rays, dtype=bool)
    for index, (normal, c) in enumerate(planes):
        denom = d @ normal
        num = c - o @ normal
        parallel = np.abs(denom) < 1e-12
        miss |= parallel & (num < 0)
        with np.errstate(divide="ignore", invalid="ignore"):
            t = num / denom
        entering = (denom < 0) & ~parallel
        exiting = (denom > 0) & ~parallel
        better = entering & (t > t_enter)
        t_enter = np.where(better, t, t_enter)
        normal_index = np.where(better, index, normal_index)
        t_exit = np.where(exiting, np.minimum(t_exit, t), t_exit)
    hit = ~miss & (t_enter <= t_exit) & (t_enter > 1e-4)
    normals = np.array([p[0] for p in planes])[normal_index]
    return np.where(hit, t_enter, np.inf), normals


def intersect(part, o_world, d_world):
    R = rotation(part["cf"])
    p = np.array(part["cf"][0:3], float)
    o = R.T @ (o_world - p)
    d = d_world @ R
    sx, sy, sz = (s / 2 for s in part["size"])
    shape = part["shape"]
    if shape == "Ball":
        r = min(part["size"]) / 2
        b = d @ o
        c = o @ o - r * r
        a = np.einsum("ij,ij->i", d, d)
        disc = b * b - a * c
        sq = np.sqrt(np.maximum(disc, 0))
        t = (-b - sq) / a
        t = np.where((disc >= 0) & (t > 1e-4), t, np.inf)
        normals = (o + d * t[:, None]) / r
    elif shape == "Cylinder":
        r = min(sy, sz)
        a = d[:, 1] ** 2 + d[:, 2] ** 2
        b = 2 * (o[1] * d[:, 1] + o[2] * d[:, 2])
        c = o[1] ** 2 + o[2] ** 2 - r * r
        disc = b * b - 4 * a * c
        sq = np.sqrt(np.maximum(disc, 0))
        with np.errstate(divide="ignore", invalid="ignore"):
            t_side = (-b - sq) / (2 * a)
        x_side = o[0] + d[:, 0] * t_side
        side_ok = (disc >= 0) & (t_side > 1e-4) & (np.abs(x_side) <= sx) & (a > 1e-12)
        t_side = np.where(side_ok, t_side, np.inf)
        best_t = t_side
        hit_side = side_ok
        cap_normal_sign = np.zeros(d.shape[0])
        for sign in (1, -1):
            with np.errstate(divide="ignore", invalid="ignore"):
                t_cap = (sign * sx - o[0]) / d[:, 0]
            y = o[1] + d[:, 1] * t_cap
            z = o[2] + d[:, 2] * t_cap
            ok = (t_cap > 1e-4) & (y * y + z * z <= r * r) & np.isfinite(t_cap)
            better = ok & (t_cap < best_t)
            best_t = np.where(better, t_cap, best_t)
            hit_side = np.where(better, False, hit_side)
            cap_normal_sign = np.where(better, sign, cap_normal_sign)
        t = best_t
        point = o + d * np.where(np.isfinite(t), t, 0)[:, None]
        side_n = np.stack([np.zeros_like(t), point[:, 1], point[:, 2]], axis=1) / max(r, 1e-6)
        cap_n = np.stack([cap_normal_sign, np.zeros_like(t), np.zeros_like(t)], axis=1)
        normals = np.where(hit_side[:, None], side_n, cap_n)
    else:
        planes = [
            (np.array([1.0, 0, 0]), sx), (np.array([-1.0, 0, 0]), sx),
            (np.array([0, 1.0, 0]), sy), (np.array([0, -1.0, 0]), sy),
            (np.array([0, 0, 1.0]), sz), (np.array([0, 0, -1.0]), sz),
        ]
        if shape == "Wedge":
            slope = np.array([0, sz, -sy])
            slope /= np.linalg.norm(slope)
            planes.append((slope, 0.0))
        t, normals = intersect_convex(o, d, planes)
    # Rays that miss carry inf/nan normals; they are discarded by the depth test.
    with np.errstate(all="ignore"):
        world_normals = np.nan_to_num(normals, posinf=0.0, neginf=0.0) @ R.T
        norm = np.linalg.norm(world_normals, axis=1, keepdims=True)
        world_normals = world_normals / np.maximum(norm, 1e-9)
    return t, world_normals


def shade(part, normals, view):
    color = np.array(part["color"], float)
    material = part.get("material")
    if material == "Neon":
        return np.clip(color * 1.15 + 0.12, 0, 1)[None, :].repeat(len(normals), 0)
    diffuse = np.clip(normals @ LIGHT, 0, 1)
    rim = np.clip(1 - np.abs(np.einsum("ij,ij->i", normals, -view)), 0, 1) ** 3
    shine = 0.25 if material in ("Metal", "Foil", "DiamondPlate", "Glass") else 0.1
    lit = color[None, :] * (0.35 + 0.75 * diffuse[:, None]) + shine * rim[:, None] * np.array([0.6, 0.55, 1.0])
    return np.clip(lit, 0, 1)


def render(parts, eye, target, width, height, fov=35):
    eye, right, up, forward = look_at(eye, target)
    img = background(height, width)
    focal = 0.5 * width / math.tan(math.radians(fov) / 2)
    xs = (np.arange(width) - width / 2 + 0.5)
    ys = (height / 2 - np.arange(height) - 0.5)
    depth = np.full((height, width), np.inf)
    translucent = []
    for part in parts:
        alpha = part["alpha"]
        if part.get("material") in ("ForceField", "Glass"):
            alpha = min(alpha, 0.55)
        center = np.array(part["cf"][0:3], float) - eye
        z = center @ forward
        radius = np.linalg.norm(part["size"]) / 2
        if z <= -radius:
            continue
        if z <= 0.1:
            x0, x1, y0, y1 = 0, width, 0, height
        else:
            cx = width / 2 + (center @ right) / z * focal
            cy = height / 2 - (center @ up) / z * focal
            pr = radius / max(z - radius, 0.1) * focal + 2
            x0, x1 = int(max(0, cx - pr)), int(min(width, cx + pr + 1))
            y0, y1 = int(max(0, cy - pr)), int(min(height, cy + pr + 1))
        if x0 >= x1 or y0 >= y1:
            continue
        gx, gy = np.meshgrid(xs[x0:x1], ys[y0:y1])
        dirs = gx[..., None] * right + gy[..., None] * up + focal * forward
        dirs = dirs.reshape(-1, 3)
        dirs /= np.linalg.norm(dirs, axis=1, keepdims=True)
        t, normals = intersect(part, eye, dirs)
        t = t.reshape(y1 - y0, x1 - x0)
        if not np.isfinite(t).any():
            continue
        colors = shade(part, normals, dirs).reshape(y1 - y0, x1 - x0, 3)
        if alpha < 0.95:
            translucent.append((z, (y0, y1, x0, x1), t, colors, alpha))
            continue
        window = depth[y0:y1, x0:x1]
        closer = t < window
        window[closer] = t[closer]
        img[y0:y1, x0:x1][closer] = colors[closer]
    for _, (y0, y1, x0, x1), t, colors, alpha in sorted(translucent, key=lambda item: -item[0]):
        visible = t < depth[y0:y1, x0:x1]
        region = img[y0:y1, x0:x1]
        region[visible] = region[visible] * (1 - alpha) + colors[visible] * alpha
    return (np.clip(img, 0, 1) * 255).astype(np.uint8)


def contact_sheet(entries, eye, target, cell, columns, title):
    rows = math.ceil(len(entries) / columns)
    sheet = Image.new("RGB", (columns * cell, rows * (cell + 26) + 40), (14, 12, 28))
    draw = ImageDraw.Draw(sheet)
    draw.text((12, 12), title, fill=(235, 225, 255))
    for index, entry in enumerate(entries):
        pixels = render(entry["parts"], eye, target, cell, cell)
        x = (index % columns) * cell
        y = 40 + (index // columns) * (cell + 26)
        sheet.paste(Image.fromarray(pixels), (x, y))
        color = RARITY_COLORS.get(entry.get("rarity"), (230, 230, 240))
        draw.text((x + 8, y + cell + 6), entry["name"], fill=color)
    return sheet


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else "build/preview.json"
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "docs/images"
    os.makedirs(out_dir, exist_ok=True)
    data = json.load(open(source))
    artifacts = contact_sheet(data["artifacts"], (5.2, 3.0, -7.4), (0, -0.1, 0), 220, 5, "VOID FACTORY - artifact previews (approximate render, not Roblox)")
    artifacts.save(os.path.join(out_dir, "artifacts.png"))
    machines = contact_sheet(data["machines"], (10, 8, -15), (0, 3.6, 0), 260, 3, "Machines (approximate render)")
    machines.save(os.path.join(out_dir, "machines.png"))
    origin = data["plot"]["origin"]
    R = rotation(origin)
    p = np.array(origin[0:3], float)
    eye = p + R @ np.array([-48.0, 46.0, -78.0])
    target = p + R @ np.array([2.0, 0.0, 4.0])
    plot = render(data["plot"]["parts"], eye, target, 1000, 620, fov=48)
    Image.fromarray(plot).save(os.path.join(out_dir, "plot.png"))
    if data.get("world"):
        world = render(data["world"]["parts"], (210.0, 170.0, 260.0), (0.0, -10.0, 20.0), 1000, 620, fov=55)
        Image.fromarray(world).save(os.path.join(out_dir, "world.png"))
    print("wrote", out_dir)


if __name__ == "__main__":
    main()
