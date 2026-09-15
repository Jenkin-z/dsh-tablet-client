from __future__ import annotations

import math
import sys
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

from PIL import Image, ImageDraw, ImageFont

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RES_DIR = PROJECT_ROOT / "android" / "app" / "src" / "main" / "res"
SVG_PATH = PROJECT_ROOT / "assets" / "icons" / "dsh_agent_icon.svg"
SIZE_MAP = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
    "adaptive": 512,
}
COLORS = {
    "bg_start": (96, 125, 139),
    "bg_end": (55, 71, 79),
    "accent": (224, 247, 250),
    "accent_strong": (128, 222, 234),
    "dot": (255, 255, 255),
}


def rounded_rectangle_mask(size: int, bbox: Sequence[int], radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    x0, y0, x1, y1 = bbox
    draw.rectangle([x0 + radius, y0, x1 - radius, y1], fill=255)
    draw.rectangle([x0, y0 + radius, x1, y1 - radius], fill=255)
    draw.ellipse([x0, y0, x0 + radius * 2, y0 + radius * 2], fill=255)
    draw.ellipse([x1 - radius * 2, y0, x1, y0 + radius * 2], fill=255)
    draw.ellipse([x0, y1 - radius * 2, x0 + radius * 2, y1], fill=255)
    draw.ellipse([x1 - radius * 2, y1 - radius * 2, x1, y1], fill=255)
    return mask


def _load_font(size: int):
    for path in [
        "C:/Windows/Fonts/arialbd.ttf",
        "C:/Windows/Fonts/ArialBD.ttf",
        "arialbd.ttf",
        "C:/Windows/Fonts/arial.ttf",
    ]:
        try:
            return ImageFont.truetype(path, size)
        except (OSError, ValueError):
            continue
    return ImageFont.load_default()


def make_icon_png(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    margin = size // 10
    radius = int(size * 0.18)
    bg_bbox = [margin, margin, size - margin, size - margin]

    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg)
    for y in range(bg_bbox[1], bg_bbox[3]):
        t = (y - bg_bbox[1]) / max(1, (bg_bbox[3] - bg_bbox[1]))
        r = int(COLORS["bg_start"][0] + (COLORS["bg_end"][0] - COLORS["bg_start"][0]) * t)
        g = int(COLORS["bg_start"][1] + (COLORS["bg_end"][1] - COLORS["bg_start"][1]) * t)
        b = int(COLORS["bg_start"][2] + (COLORS["bg_end"][2] - COLORS["bg_start"][2]) * t)
        bg_draw.line([(bg_bbox[0], y), (bg_bbox[2], y)], fill=(r, g, b, 255))
    mask = rounded_rectangle_mask(size, bg_bbox, radius)
    img = Image.composite(bg, img, mask)
    draw = ImageDraw.Draw(img)

    cx, cy = size // 2, size // 2
    max_radius = size // 2 - margin - radius

    # subtle glow
    glow_radius = int(size * 0.34)
    draw.ellipse(
        [cx - glow_radius, cy - glow_radius, cx + glow_radius, cy + glow_radius],
        fill=(128, 222, 234, 70),
    )

    # white badge
    badge_radius = int(size * 0.30)
    draw.ellipse(
        [cx - badge_radius, cy - badge_radius, cx + badge_radius, cy + badge_radius],
        fill=(255, 255, 255, 255),
    )

    # text
    font = _load_font(max(12, int(size * 0.34)))
    text = "DSH"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    x = cx - text_w // 2
    y = cy - text_h // 2 - bbox[1] // 2
    draw.text((x, y), text, fill=(96, 125, 139, 255), font=font)

    return img


def resolve_color(value: str, alpha: int = 255):
    value = value.strip().lower()
    if value.startswith("#"):
        hex_value = value[1:]
        if len(hex_value) == 3:
            r = int(hex_value[0] * 2, 16)
            g = int(hex_value[1] * 2, 16)
            b = int(hex_value[2] * 2, 16)
        else:
            r = int(hex_value[0:2], 16)
            g = int(hex_value[2:4], 16)
            b = int(hex_value[4:6], 16)
        return (r, g, b, alpha)
    if value in ("none", "transparent"):
        return None
    raise ValueError(f"unsupported color: {value}")


def sample_gradient_stops(stops, t: float):
    if not stops:
        return (0, 0, 0, 0)
    stops = sorted(stops, key=lambda item: item[0])
    if t <= stops[0][0]:
        return stops[0][1]
    if t >= stops[-1][0]:
        return stops[-1][1]
    for idx in range(len(stops) - 1):
        offset0, color0 = stops[idx]
        offset1, color1 = stops[idx + 1]
        if offset0 <= t <= offset1:
            local_t = (t - offset0) / max(1e-6, offset1 - offset0)
            return (
                int(color0[0] + (color1[0] - color0[0]) * local_t),
                int(color0[1] + (color1[1] - color0[1]) * local_t),
                int(color0[2] + (color1[2] - color0[2]) * local_t),
                int(color0[3] + (color1[3] - color0[3]) * local_t),
            )
    return stops[-1][1]


def draw_rounded_rectangle(draw: ImageDraw.ImageDraw, bbox, radius: float, fill, outline, width: int):
    x0, y0, x1, y1 = bbox
    draw.rounded_rectangle(bbox, radius=radius, fill=fill, outline=outline, width=width)


def parse_gradient_attrs(attrs: dict[str, str], gradient_type: str) -> dict:
    parsed: dict = {"type": gradient_type, "stops": []}
    for key, value in attrs.items():
        if key.startswith("stop-"):
            parsed["stops"].append((float(key[5:]), resolve_color(value)))
        elif key in ("x1", "y1", "x2", "y2", "cx", "cy", "r", "fx", "fy"):
            parsed[key] = float(value) / 100 if "%" in value else float(value)
        elif key == "gradientUnits":
            parsed[key] = value
    return parsed


def apply_linear(draw: ImageDraw.ImageDraw, size: int, scale: float, bounds, gradient):
    x0, y0, x1, y1 = bounds
    gx0, gy0 = gradient.get("x1", 0), gradient.get("y1", 0)
    gx1, gy1 = gradient.get("x2", 1), gradient.get("y2", 0)
    if gradient.get("gradientUnits") == "objectBoundingBox":
        gx0 = x0 + (x1 - x0) * gx0
        gy0 = y0 + (y1 - y0) * gy0
        gx1 = x0 + (x1 - x0) * gx1
        gy1 = y0 + (y1 - y0) * gy1
    else:
        gx0 *= scale
        gy0 *= scale
        gx1 *= scale
        gy1 *= scale
    for y in range(max(0, int(y0)), min(size, int(math.ceil(y1)))):
        t = (y - gy0) / max(1e-6, gy1 - gy0)
        color = sample_gradient_stops(gradient["stops"], t)
        if color:
            draw.line([(x0, y), (x1, y)], fill=color)


def apply_radial(img: Image.Image, size: int, bounds, gradient):
    x0, y0, x1, y1 = bounds
    cx = gradient.get("cx", 0.5)
    cy = gradient.get("cy", 0.5)
    r = gradient.get("r", 0.5)
    if gradient.get("gradientUnits") == "objectBoundingBox":
        cx = x0 + (x1 - x0) * cx
        cy = y0 + (y1 - y0) * cy
        r = min(x1 - x0, y1 - y0) * r
    else:
        cx *= size
        cy *= size
        r *= size
    for y in range(size):
        for x in range(size):
            dist = math.hypot(x - cx, y - cy)
            t = min(1.0, dist / max(1e-6, r))
            color = sample_gradient_stops(gradient["stops"], t)
            if color:
                img.putpixel((x, y), color)


def transform_point(point, transforms):
    x, y = point
    for transform in reversed(transforms):
        for part in transform.split(")"):
            part = part.strip()
            if not part:
                continue
            if part.startswith("translate("):
                nums = part[10:].split(",")
                if len(nums) == 1:
                    x += float(nums[0])
                    y += float(nums[0])
                else:
                    x += float(nums[0])
                    y += float(nums[1])
            elif part.startswith("scale("):
                nums = part[6:].split(",")
                if len(nums) == 1:
                    x *= float(nums[0])
                    y *= float(nums[0])
                else:
                    x *= float(nums[0])
                    y *= float(nums[1])
            elif part.startswith("rotate("):
                angle = math.radians(float(part[7:]))
                cos = math.cos(angle)
                sin = math.sin(angle)
                x, y = x * cos - y * sin, x * sin + y * cos
    return x, y


def parse_path(d: str):
    commands = []
    tokens = []
    current = ""
    for char in d:
        if char in "+-.eE" and current and current[-1] not in "+-.eE":
            tokens.append(current)
            current = char
        elif char in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ":
            if current:
                tokens.append(current)
            tokens.append(char)
            current = ""
        else:
            current += char
    if current:
        tokens.append(current)

    idx = 0
    while idx < len(tokens):
        token = tokens[idx]
        if token in "0123456789.eE-+":
            idx += 1
            continue
        if token in "mMlLhHvVcCsSaAzZqQtT":
            count = {
                "m": 2, "M": 2, "l": 2, "L": 2, "t": 2, "T": 2,
                "s": 4, "S": 4, "q": 4, "Q": 4,
                "c": 6, "C": 6, "a": 7, "A": 7,
                "h": 1, "H": 1, "v": 1, "V": 1,
                "z": 0, "Z": 0,
            }[token]
            args = []
            for i in range(count):
                if idx + 1 + i < len(tokens):
                    args.append(float(tokens[idx + 1 + i]))
            commands.append({"kind": token, "args": args})
            idx += count + 1
        else:
            idx += 1
    return commands


def draw_path_commands(draw: ImageDraw.ImageDraw, commands, transforms, fill, stroke, stroke_width):
    def pt(p):
        return transform_point((p[0] * scale, p[1] * scale), transforms)

    def line(p0, p1):
        if stroke:
            draw.line([pt(p0), pt(p1)], fill=stroke, width=int(stroke_width * scale))

    idx = 0
    current = (0.0, 0.0)
    start = current
    while idx < len(commands):
        cmd = commands[idx]
        kind = cmd["kind"]
        if kind == "M":
            current = (cmd["args"][0], cmd["args"][1])
            start = current
        elif kind == "m":
            current = (current[0] + cmd["args"][0], current[1] + cmd["args"][1])
            start = current
        elif kind in ("L", "l"):
            if kind == "L":
                current = (cmd["args"][0], cmd["args"][1])
            else:
                current = (current[0] + cmd["args"][0], current[1] + cmd["args"][1])
            line(current, current)
        elif kind in ("H", "h"):
            if kind == "H":
                current = (cmd["args"][0], current[1])
            else:
                current = (current[0] + cmd["args"][0], current[1])
            line(current, current)
        elif kind in ("V", "v"):
            if kind == "V":
                current = (current[0], cmd["args"][0])
            else:
                current = (current[0], current[1] + cmd["args"][0])
            line(current, current)
        elif kind in ("Z", "z"):
            if start:
                line(current, start)
            current = start
        elif kind in ("C", "c"):
            if kind == "C":
                target = (cmd["args"][4], cmd["args"][5])
            else:
                target = (current[0] + cmd["args"][4], current[1] + cmd["args"][5])
            line(current, target)
            current = target
        elif kind in ("A", "a"):
            rx, ry = cmd["args"][2], cmd["args"][3]
            if kind == "A":
                target = (cmd["args"][5], cmd["args"][6])
            else:
                target = (current[0] + cmd["args"][5], current[1] + cmd["args"][6])
            bbox = [
                min(current[0], target[0]) - rx,
                min(current[1], target[1]) - ry,
                max(current[0], target[0]) + rx,
                max(current[1], target[1]) + ry,
            ]
            start_angle = math.degrees(math.atan2(current[1] - 256, current[0] - 256))
            end_angle = math.degrees(math.atan2(target[1] - 256, target[0] - 256))
            draw.arc(
                [bbox[0] * scale, bbox[1] * scale, bbox[2] * scale, bbox[3] * scale],
                start=start_angle,
                end=end_angle,
                fill=stroke,
                width=int(stroke_width * scale),
            )
            current = target
        idx += 1


def process_element(element, transforms, draw, img, size, scale, gradients):
    tag = element["tag"]
    attrs = element["attrs"]
    if tag in ("defs", "stop"):
        return
    if tag in ("linearGradient", "radialGradient"):
        gradients[attrs.get("id", "")] = parse_gradient_attrs(attrs, tag)
        for child in element.get("children", []):
            process_element(child, transforms, draw, img, size, scale, gradients)
        return
    fill_value = attrs.get("fill", "none")
    stroke_value = attrs.get("stroke", "none")
    stroke_width = float(attrs.get("stroke-width", 1))
    if tag == "rect":
        x = float(attrs.get("x", 0))
        y = float(attrs.get("y", 0))
        w = float(attrs.get("width", 0))
        h = float(attrs.get("height", 0))
        rx = float(attrs.get("rx", 0))
        bbox = [x, y, x + w, y + h]
        fill = resolve_color(fill_value) if fill_value.startswith("url(#") else resolve_color(fill_value)
        outline = resolve_color(stroke_value) if stroke_value not in ("none",) else None
        if fill_value.startswith("url(#"):
            apply_linear(draw, size, scale, bbox, gradients[fill_value[5:-1]])
            fill = None
        draw_rounded_rectangle(draw, [v * scale for v in bbox], rx * scale, fill, outline, int(stroke_width))
    elif tag == "circle":
        cx = float(attrs.get("cx", 0))
        cy = float(attrs.get("cy", 0))
        r = float(attrs.get("r", 0))
        bbox = [cx - r, cy - r, cx + r, cy + r]
        fill = resolve_color(fill_value) if not fill_value.startswith("url(#") else None
        outline = resolve_color(stroke_value) if stroke_value not in ("none",) else None
        if fill_value.startswith("url(#"):
            apply_radial(img, size, bbox, gradients[fill_value[5:-1]])
        draw.ellipse([v * scale for v in bbox], fill=fill, outline=outline, width=int(stroke_width))
    elif tag == "path":
        commands = parse_path(attrs.get("d", ""))
        stroke = resolve_color(stroke_value) if stroke_value not in ("none",) else None
        if fill_value.startswith("url(#"):
            apply_radial(img, size, [0, 0, 512, 512], gradients[fill_value[5:-1]])
        draw_path_commands(draw, transforms, None, stroke, stroke_width)
    elif tag == "g":
        child_transforms = transforms + [attrs.get("transform", "")]
        for child in element.get("children", []):
            process_element(child, child_transforms, draw, img, size, scale, gradients)
    elif tag == "svg":
        for child in element.get("children", []):
            process_element(child, transforms, draw, img, size, scale, gradients)


def rasterize_svg(svg_text: str, size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    scale = size / 512.0
    gradients: dict[str, dict] = {}

    stack: list[dict] = []
    current: Optional[dict] = None
    root: Optional[dict] = None

    for token in svg_text.replace("/>", " >").replace("<", "\n<").replace(">", ">\n").splitlines():
        token = token.strip()
        if not token:
            continue
        if token.startswith("</"):
            if current:
                stack.pop()
                current = stack[-1] if stack else None
            continue
        if token.startswith("<"):
            if current:
                stack.append(current)
            tag = token.strip("<>").split(" ")[0].split(">")[0]
            attrs: dict[str, str] = {}
            attr_text = token[len(tag) + 1 : -1]
            parts = attr_text.split('" ')
            idx = 0
            while idx < len(parts):
                part = parts[idx].strip()
                if not part:
                    idx += 1
                    continue
                if "=" in part:
                    key, value = part.split("=", 1)
                    if value.startswith('"'):
                        if value.endswith('"') and len(value) > 1:
                            value = value[1:-1]
                        else:
                            value = value[1:] + ' "' + (parts[idx + 1] if idx + 1 < len(parts) else "")
                            idx += 1
                    attrs[key] = value
                idx += 1
            current = {"tag": tag, "attrs": attrs, "children": []}
            if root is None:
                root = current
            else:
                stack.append(current)
        elif current is not None:
            pass

    if root is not None:
        process_element(root, [], draw, img, size, scale, gradients)
    return img


def write_icons(source: str = "png", extra_sizes: Optional[Sequence[int]] = None) -> List[Path]:
    paths: List[Path] = []
    if source == "svg":
        svg_text = SVG_PATH.read_text(encoding="utf-8")
        for name, size in SIZE_MAP.items():
            if name == "adaptive":
                target_dir = RES_DIR / "drawable"
                target_dir.mkdir(parents=True, exist_ok=True)
                img = rasterize_svg(svg_text, size)
                path = target_dir / "ic_launcher_foreground.png"
                img.save(path, format="PNG")
                paths.append(path)
                bg_path = target_dir / "ic_launcher_background.png"
                bg = Image.new("RGBA", (size, size), (96, 125, 139, 255))
                bg.save(bg_path, format="PNG")
                paths.append(bg_path)
            else:
                target_dir = RES_DIR / f"mipmap-{name}"
                target_dir.mkdir(parents=True, exist_ok=True)
                img = rasterize_svg(svg_text, size)
                path = target_dir / "ic_launcher.png"
                img.save(path, format="PNG")
                paths.append(path)
    else:
        for name, size in SIZE_MAP.items():
            if name == "adaptive":
                target_dir = RES_DIR / "drawable"
                target_dir.mkdir(parents=True, exist_ok=True)
                img = make_icon_png(size)
                path = target_dir / "ic_launcher_foreground.png"
                img.save(path, format="PNG")
                paths.append(path)
                bg_path = target_dir / "ic_launcher_background.png"
                bg = Image.new("RGBA", (size, size), (96, 125, 139, 255))
                bg.save(bg_path, format="PNG")
                paths.append(bg_path)
            else:
                target_dir = RES_DIR / f"mipmap-{name}"
                target_dir.mkdir(parents=True, exist_ok=True)
                img = make_icon_png(size)
                path = target_dir / "ic_launcher.png"
                img.save(path, format="PNG")
                paths.append(path)

    if extra_sizes:
        for size in extra_sizes:
            target_dir = RES_DIR / "mipmap-anydpi-v26"
            target_dir.mkdir(parents=True, exist_ok=True)
            img = make_icon_png(size)
            path = target_dir / f"ic_launcher_{size}.png"
            img.save(path, format="PNG")
            paths.append(path)
    return paths


def check_icons() -> List[Tuple[Path, Tuple[int, int, str]]]:
    results = []
    for path in sorted(RES_DIR.rglob("ic_launcher.png")):
        with Image.open(path) as im:
            results.append((path, (im.width, im.height, im.mode)))
    for path in [RES_DIR / "drawable" / "ic_launcher_foreground.png", RES_DIR / "drawable" / "ic_launcher_background.png"]:
        if path.exists():
            with Image.open(path) as im:
                results.append((path, (im.width, im.height, im.mode)))
    return results


def print_icon_paths() -> None:
    for path in sorted(RES_DIR.rglob("ic_launcher.png")):
        print(path)
    for path in [RES_DIR / "drawable" / "ic_launcher_foreground.png", RES_DIR / "drawable" / "ic_launcher_background.png"]:
        if path.exists():
            print(path)


def main(argv: Optional[Sequence[str]] = None) -> int:
    argv = list(argv or sys.argv[1:])
    if "--check" in argv:
        for path, meta in check_icons():
            print(path, meta)
        return 0
    if "--check-paths" in argv:
        print_icon_paths()
        return 0
    source = "png"
    extra: List[int] = []
    if "--source" in argv:
        source = argv[argv.index("--source") + 1]
    if "--extra-size" in argv:
        extra = [int(v) for v in argv[argv.index("--extra-size") + 1].split(",") if v]
    paths = write_icons(source=source, extra_sizes=extra)
    for path in paths:
        print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
