#!/usr/bin/env python3
"""Measure a reference image for framework construction: colors, pixel probes, element boxes.

Brand-agnostic: knows nothing about any brand's tokens, colors, or fonts. Reads one image with
Pillow, never touches the network, and prints JSON to stdout so the values can be compared with
the brand palette (B1) and converted to proportions of the canvas (B5 sizes, B6 positions).

Examples:
    python measure_reference.py --image reference.png
    python measure_reference.py --image reference.png --palette 5 --probe 90,265 --probe 540,40
    python measure_reference.py --image reference.png --box 60,90,600,230
    python measure_reference.py --image reference.png --box 60,90,600,230 --background "#043673" --tolerance 30
"""
import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, UnidentifiedImageError


def parse_args():
    parser = argparse.ArgumentParser(
        description="Measure a reference image: dominant colors, pixel probes and element bounding boxes (JSON)."
    )
    parser.add_argument("--image", type=str, required=True, help="Path to the reference image.")
    parser.add_argument(
        "--palette",
        type=int,
        default=8,
        help="Report the top N colors by area after quantizing (1-256). Default: 8.",
    )
    parser.add_argument(
        "--probe",
        type=str,
        action="append",
        default=[],
        metavar="X,Y",
        help="Report the hex color of the pixel at X,Y. Repeatable.",
    )
    parser.add_argument(
        "--box",
        type=str,
        action="append",
        default=[],
        metavar="X0,Y0,X1,Y1",
        help="Find the bounding box of non-background pixels inside this region. Repeatable.",
    )
    parser.add_argument(
        "--background",
        type=str,
        default=None,
        help="Background hex for --box (e.g. '#043673'). Default: the most common pixel color.",
    )
    parser.add_argument(
        "--tolerance",
        type=int,
        default=40,
        help="Max per-channel difference (0-255) still counted as background for --box. Default: 40.",
    )
    return parser.parse_args()


def _hex(rgb) -> str:
    return "#{:02X}{:02X}{:02X}".format(*rgb[:3])


def _parse_hex(value: str):
    raw = value.strip().lstrip("#")
    if len(raw) != 6:
        sys.exit(f"error: --background must be a 6-digit hex like '#043673' (got {value!r})")
    try:
        return tuple(int(raw[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        sys.exit(f"error: --background must be a 6-digit hex like '#043673' (got {value!r})")


def _parse_ints(value: str, count: int, flag: str):
    parts = value.split(",")
    if len(parts) != count:
        sys.exit(f"error: {flag} expects {count} comma-separated integers (got {value!r})")
    try:
        return [int(p.strip()) for p in parts]
    except ValueError:
        sys.exit(f"error: {flag} expects {count} comma-separated integers (got {value!r})")


def _pct(value: int, total: int) -> float:
    return round(value * 100.0 / total, 2)


def _most_common(img: Image.Image):
    width, height = img.size
    colors = img.getcolors(maxcolors=width * height)
    return max(colors, key=lambda item: item[0])[1]


def _palette(img: Image.Image, count: int):
    width, height = img.size
    quantized = img.quantize(colors=count, method=Image.Quantize.MEDIANCUT)
    flat = quantized.getpalette()
    counts = sorted(quantized.getcolors(maxcolors=256), key=lambda item: (-item[0], item[1]))
    result = []
    for pixels, index in counts[:count]:
        rgb = flat[index * 3:index * 3 + 3]
        result.append({"hex": _hex(rgb), "share": _pct(pixels, width * height)})
    return result


def _box(img: Image.Image, region, background, tolerance: int):
    width, height = img.size
    x0, y0, x1, y1 = region
    crop = img.crop((x0, y0, x1, y1))
    diff = ImageChops.difference(crop, Image.new("RGB", crop.size, background))
    r, g, b = diff.split()
    strongest = ImageChops.lighter(ImageChops.lighter(r, g), b)
    mask = strongest.point(lambda v: 255 if v > tolerance else 0)
    found = mask.getbbox()
    entry = {"region": [x0, y0, x1, y1], "background": _hex(background), "tolerance": tolerance}
    if found is None:
        entry["found"] = False
        return entry
    left, top, right, bottom = found[0] + x0, found[1] + y0, found[2] + x0, found[3] + y0
    entry["found"] = True
    entry["px"] = {
        "left": left,
        "top": top,
        "right": right,
        "bottom": bottom,
        "width": right - left,
        "height": bottom - top,
    }
    entry["percent"] = {
        "left": _pct(left, width),
        "top": _pct(top, height),
        "right": _pct(right, width),
        "bottom": _pct(bottom, height),
        "width": _pct(right - left, width),
        "height": _pct(bottom - top, height),
    }
    return entry


def main() -> None:
    args = parse_args()

    if not (1 <= args.palette <= 256):
        sys.exit(f"error: --palette must be between 1 and 256 (got {args.palette})")
    if not (0 <= args.tolerance <= 255):
        sys.exit(f"error: --tolerance must be between 0 and 255 (got {args.tolerance})")

    image_path = Path(args.image).resolve()
    if not image_path.is_file():
        sys.exit(f"error: image file not found: {image_path}")
    try:
        with Image.open(image_path) as source:
            img = source.convert("RGB")
    except (UnidentifiedImageError, OSError) as exc:
        sys.exit(f"error: cannot read image {image_path}: {exc}")

    width, height = img.size

    probes = []
    for value in args.probe:
        x, y = _parse_ints(value, 2, "--probe")
        if not (0 <= x < width and 0 <= y < height):
            sys.exit(f"error: --probe {x},{y} is outside the canvas ({width}x{height})")
        probes.append({"x": x, "y": y, "hex": _hex(img.getpixel((x, y)))})

    regions = []
    for value in args.box:
        x0, y0, x1, y1 = _parse_ints(value, 4, "--box")
        if not (0 <= x0 < x1 <= width and 0 <= y0 < y1 <= height):
            sys.exit(
                f"error: --box {value} must satisfy 0 <= X0 < X1 <= {width} and 0 <= Y0 < Y1 <= {height}"
            )
        regions.append((x0, y0, x1, y1))

    background = _parse_hex(args.background) if args.background else _most_common(img)

    report = {
        "image": str(image_path),
        "canvas": {"width": width, "height": height},
        "palette": _palette(img, args.palette),
        "probes": probes,
        "boxes": [_box(img, region, background, args.tolerance) for region in regions],
    }
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
