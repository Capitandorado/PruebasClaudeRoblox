#!/usr/bin/env python3
"""Approximate screenshots of VOID FACTORY's interface (NOT Roblox's renderer).

Lays out the exported GUI tree the way Roblox does for the features the game uses
(Size/Position/AnchorPoint, UIPadding, UIListLayout, UIGridLayout, UIScale on the ScreenGui,
UISizeConstraint, ClipsDescendants) and draws it with Pillow, to catch overlaps and
off-screen elements without Studio. Emoji are drawn as small circles.

    lune run tools/preview/export_ui.luau build/ui.json
    python3 tools/preview/render_ui.py build/ui.json build/ui
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

TOPBAR = 58
FONT_PATHS = [
    "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]
_fonts = {}


def font(size):
    size = max(6, int(size))
    if size not in _fonts:
        for path in FONT_PATHS:
            if os.path.exists(path):
                _fonts[size] = ImageFont.truetype(path, size)
                break
        else:
            _fonts[size] = ImageFont.load_default(size=size)
    return _fonts[size]


def clean(text):
    out = []
    for ch in text:
        code = ord(ch)
        if code > 0x2190 and ch not in "★•—→✓✕⚡":
            out.append("●")  # icon placeholder
        elif 0xFE00 <= code <= 0xFE0F:
            continue
        else:
            out.append(ch)
    return "".join(out)


def rgb(c, alpha=1.0):
    return (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), int(max(0, min(1, alpha)) * 255))


def gui_children(node):
    return [c for c in node.get("children", []) if c.get("visible", True)]


def resolve_size(node, pw, ph):
    s = node["size"]
    w = s[0] * pw + s[1]
    h = s[2] * ph + s[3]
    if node.get("maxSize"):
        w = min(w, node["maxSize"][0])
        h = min(h, node["maxSize"][1])
    return max(0, w), max(0, h)


def place(node, x, y, w, h, out, clip):
    node["_rect"] = (x, y, w, h)
    node["_clip"] = clip
    out.append(node)
    pad = node.get("padding") or [0, 0, 0, 0]
    cx, cy = x + pad[2], y + pad[0]
    cw, ch = max(0, w - pad[2] - pad[3]), max(0, h - pad[0] - pad[1])
    child_clip = clip
    if node.get("clips"):
        child_clip = intersect(clip, (x, y, w, h))
    kids = sorted(gui_children(node), key=lambda c: c.get("order", 0))
    layout = node.get("layout")
    if layout and layout["type"] == "list":
        sizes = [resolve_size(k, cw, ch) for k in kids]
        gap = layout["padding"][0] * (ch if layout["fill"] == "Vertical" else cw) + layout["padding"][1]
        if layout["fill"] == "Vertical":
            total = sum(s[1] for s in sizes) + gap * max(0, len(kids) - 1)
            cursor = cy + {"Top": 0, "Center": (ch - total) / 2, "Bottom": ch - total}.get(layout["vAlign"], 0)
            for kid, (kw, kh) in zip(kids, sizes):
                kx = cx + {"Left": 0, "Center": (cw - kw) / 2, "Right": cw - kw}.get(layout["hAlign"], 0)
                place(kid, kx, cursor, kw, kh, out, child_clip)
                cursor += kh + gap
        else:
            total = sum(s[0] for s in sizes) + gap * max(0, len(kids) - 1)
            cursor = cx + {"Left": 0, "Center": (cw - total) / 2, "Right": cw - total}.get(layout["hAlign"], 0)
            for kid, (kw, kh) in zip(kids, sizes):
                ky = cy + {"Top": 0, "Center": (ch - kh) / 2, "Bottom": ch - kh}.get(layout["vAlign"], 0)
                place(kid, cursor, ky, kw, kh, out, child_clip)
                cursor += kw + gap
    elif layout and layout["type"] == "grid":
        cell = layout["cell"]
        pad_ = layout["cellPad"]
        cwid = cell[0] * cw + cell[1]
        chei = cell[2] * ch + cell[3]
        px = pad_[0] * cw + pad_[1]
        py = pad_[2] * ch + pad_[3]
        n = len(kids)
        if layout["fill"] == "Horizontal":
            per = max(1, int((cw + px) // (cwid + px)) if cwid + px > 0 else 1)
            if layout.get("maxCells"):
                per = min(per, layout["maxCells"])
            rows = (n + per - 1) // per
            used_h = rows * chei + max(0, rows - 1) * py
            used_w = min(n, per) * cwid + max(0, min(n, per) - 1) * px
            oy = {"Top": 0, "Center": (ch - used_h) / 2, "Bottom": ch - used_h}.get(layout["vAlign"], 0)
            ox = {"Left": 0, "Center": (cw - used_w) / 2, "Right": cw - used_w}.get(layout["hAlign"], 0)
            for i, kid in enumerate(kids):
                place(kid, cx + ox + (i % per) * (cwid + px), cy + oy + (i // per) * (chei + py), cwid, chei, out, child_clip)
        else:
            per = max(1, int((ch + py) // (chei + py)) if chei + py > 0 else 1)
            if layout.get("maxCells"):
                per = min(per, layout["maxCells"])
            cols = (n + per - 1) // per
            used_h = min(n, per) * chei + max(0, min(n, per) - 1) * py
            used_w = cols * cwid + max(0, cols - 1) * px
            oy = {"Top": 0, "Center": (ch - used_h) / 2, "Bottom": ch - used_h}.get(layout["vAlign"], 0)
            ox = {"Left": 0, "Center": (cw - used_w) / 2, "Right": cw - used_w}.get(layout["hAlign"], 0)
            for i, kid in enumerate(kids):
                place(kid, cx + ox + (i // per) * (cwid + px), cy + oy + (i % per) * (chei + py), cwid, chei, out, child_clip)
    else:
        for kid in sorted(kids, key=lambda c: c.get("z", 1)):
            kw, kh = resolve_size(kid, cw, ch)
            p = kid["pos"]
            kx = cx + p[0] * cw + p[1] - kid["anchor"][0] * kw
            ky = cy + p[2] * ch + p[3] - kid["anchor"][1] * kh
            place(kid, kx, ky, kw, kh, out, child_clip)


def intersect(a, b):
    x0, y0 = max(a[0], b[0]), max(a[1], b[1])
    x1 = min(a[0] + a[2], b[0] + b[2])
    y1 = min(a[1] + a[3], b[1] + b[3])
    return (x0, y0, max(0, x1 - x0), max(0, y1 - y0))


def draw_node(img, node, scale):
    x, y, w, h = node["_rect"]
    clip = node["_clip"]
    visible = intersect(clip, (x, y, w, h))
    if visible[2] <= 0 or visible[3] <= 0:
        return
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    box = [x * scale, y * scale, (x + w) * scale - 1, (y + h) * scale - 1]
    radius = int((node.get("corner") or 0) * scale)
    if node["class"] == "ViewportFrame":
        d.rounded_rectangle(box, radius=radius, fill=(12, 10, 26, 255), outline=(90, 80, 160, 255))
        d.text((box[0] + 6, box[1] + 4), "3D preview", fill=(150, 140, 200, 255), font=font(11 * scale))
    elif node.get("bgT", 1) < 0.99:
        fill = rgb(node["bg"], 1 - node["bgT"])
        stroke = node.get("stroke")
        outline = rgb(stroke["color"], 1 - stroke["t"]) if stroke else None
        width = max(1, int(stroke["thickness"] * scale)) if stroke else 0
        d.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)
    elif node.get("stroke"):
        stroke = node["stroke"]
        d.rounded_rectangle(box, radius=radius, outline=rgb(stroke["color"], 1 - stroke["t"]), width=max(1, int(stroke["thickness"] * scale)))
    text = node.get("text")
    if text and node.get("textT", 0) < 0.99:
        size = node.get("textSize", 14)
        if node.get("textScaled"):
            size = h * 0.7
        f = font(size * scale)
        lines = clean(text).split("\n")
        if node.get("wrapped"):
            wrapped = []
            for line in lines:
                words = line.split(" ")
                current = ""
                for word in words:
                    trial = (current + " " + word).strip()
                    if d.textlength(trial, font=f) <= w * scale or not current:
                        current = trial
                    else:
                        wrapped.append(current)
                        current = word
                wrapped.append(current)
            lines = wrapped
        line_h = f.size * 1.2
        total_h = line_h * len(lines)
        ty = box[1] + {"Top": 0, "Center": (h * scale - total_h) / 2, "Bottom": h * scale - total_h}.get(node.get("yAlign", "Center"), (h * scale - total_h) / 2)
        for line in lines:
            tw = d.textlength(line, font=f)
            tx = box[0] + {"Left": 0, "Center": (w * scale - tw) / 2, "Right": w * scale - tw}.get(node.get("xAlign", "Center"), 0)
            d.text((tx, ty), line, fill=rgb(node["textColor"], 1 - node.get("textT", 0)), font=f)
            ty += line_h
    cx0, cy0 = int(visible[0] * scale), int(visible[1] * scale)
    cx1, cy1 = int((visible[0] + visible[2]) * scale), int((visible[1] + visible[3]) * scale)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rectangle([cx0, cy0, cx1, cy1], fill=255)
    img.paste(layer, (0, 0), Image.composite(layer, Image.new("RGBA", img.size, (0, 0, 0, 0)), mask))


def render_scene(scene, out_dir):
    vw, vh = scene["viewport"]
    tree = scene["tree"]
    scale = tree.get("scale", 1.0)
    # The ScreenGui sits below the Roblox top bar; layout happens in design units.
    gw, gh = vw / scale, (vh - TOPBAR) / scale
    img = Image.new("RGBA", (vw, vh), (40, 30, 70, 255))
    bg = ImageDraw.Draw(img)
    for i in range(vh):
        t = i / vh
        bg.line([(0, i), (vw, i)], fill=(int(20 + 30 * t), int(14 + 20 * t), int(40 + 50 * t), 255))
    bg.rectangle([0, 0, vw, TOPBAR], fill=(10, 10, 14, 255))
    bg.text((12, 18), "Roblox top bar", fill=(120, 120, 130, 255), font=font(14))
    nodes = []
    root_clip = (0, 0, gw, gh)
    tree["size"] = [0, gw, 0, gh]
    place({"children": tree["children"], "size": [0, gw, 0, gh], "pos": [0, 0, 0, 0], "anchor": [0, 0], "visible": True, "class": "Root"}, 0, 0, gw, gh, nodes, root_clip)
    canvas = Image.new("RGBA", (vw, vh - TOPBAR), (0, 0, 0, 0))
    for node in nodes:
        if node.get("class") == "Root":
            continue
        draw_node(canvas, node, scale)
    img.paste(canvas, (0, TOPBAR), canvas)
    path = os.path.join(out_dir, scene["name"] + ".png")
    img.convert("RGB").save(path)
    return path


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else "build/ui.json"
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "build/ui"
    os.makedirs(out_dir, exist_ok=True)
    data = json.load(open(source))
    only = sys.argv[3] if len(sys.argv) > 3 else None
    for scene in data["scenes"]:
        if only and only not in scene["name"]:
            continue
        print(render_scene(scene, out_dir))


if __name__ == "__main__":
    main()
