---
name: decodex-render-pipeline
description: Deterministic, pre-built scripts to export an HTML piece to a raster image (PNG/JPEG/WebP) with an exact pixel clip, to scale/resize an existing image, and to measure a reference image (colors, element boxes) for framework construction. Use this skill any time a piece needs to be rendered to an image file or an image needs to be resized — invoke these scripts instead of writing new rendering or resizing code from scratch.
compatibility: Requires Python 3.9+, and Playwright (with Chromium installed) and Pillow in the project's .venv.
metadata:
  version: "0.1.0"
---

# Decodex Render Pipeline

## Why this skill exists

A shared render helper that only supports a square clip forces every non-square builder
(9:16 stories, banners) to hand-roll its own near-identical screenshot function. That is exactly
the class of improvised, one-off code this skill exists to prevent, for any brand.

**Do not write your own HTML→image rendering code or your own image-resizing code.** Use the
scripts below instead. They are brand-agnostic — they know nothing about any brand's tokens,
colors, or fonts — and are meant to be the one shared tool every framework/builder calls.

## `scripts/export_piece.py` — render an HTML piece to an image

Renders an HTML file (or an inline HTML string) with headless Chromium and captures an **exact**
`width x height` clip — never assumes a square canvas.

```
.venv/bin/python .claude/skills/decodex-render-pipeline/scripts/export_piece.py --html piece.html --width 1080 --height 1920 --output out.png
.venv/bin/python .claude/skills/decodex-render-pipeline/scripts/export_piece.py --html-string "<html>...</html>" --width 300 --height 250 --output out.jpg --format jpeg
.venv/bin/python .claude/skills/decodex-render-pipeline/scripts/export_piece.py --html piece.html --width 1080 --height 1920 --output out.png --scale 2
```

Arguments:

- `--html` **or** `--html-string` (exactly one, required) — the HTML source.
- `--width`, `--height` (required) — exact clip size in px.
- `--output` (required) — output file path; parent directories are created automatically.
- `--format` — `png` (default), `jpeg`/`jpg`, or `webp`.
- `--scale` — device scale factor for higher-resolution export (e.g. `2` for a @2x asset).
  Default `1.0`.
- `--quality` — 1–100, applies to `jpeg`/`webp` only. Default `90`.

Implementation note: Playwright's `page.screenshot()` natively supports `png` and `jpeg` only.
`webp` output is captured as PNG bytes in memory and converted with Pillow.

## `scripts/scale_image.py` — resize an existing image

```
.venv/bin/python .claude/skills/decodex-render-pipeline/scripts/scale_image.py --input piece.png --output piece_small.png --width 540
.venv/bin/python .claude/skills/decodex-render-pipeline/scripts/scale_image.py --input piece.png --output piece_small.png --height 960
.venv/bin/python .claude/skills/decodex-render-pipeline/scripts/scale_image.py --input piece.png --output piece_2x.png --scale 2.0
.venv/bin/python .claude/skills/decodex-render-pipeline/scripts/scale_image.py --input piece.png --output thumb.jpg --width 300 --height 300
```

Arguments:

- `--input`, `--output` (required).
- `--width` and/or `--height` — if only one is given, aspect ratio is preserved. Mutually
  exclusive with `--scale`.
- `--scale` — uniform factor (e.g. `0.5`, `2.0`). Mutually exclusive with `--width`/`--height`.
- `--format` — forces an output format; otherwise inferred from `--output`'s extension.
- `--quality` — 1–100, applies to lossy formats only. Default `90`.

Uses `Image.LANCZOS` resampling.

## `scripts/measure_reference.py` — measure a reference image

Measures a reference image for framework construction (see
`.claude/knowledge/framework-construction.md`, step 0): its dominant colors, the exact color at a
point, and the bounding box of an element. Prints JSON to stdout with the canvas width/height;
Pillow only, no network.

```
.venv/bin/python .claude/skills/decodex-render-pipeline/scripts/measure_reference.py --image reference.png
.venv/bin/python .claude/skills/decodex-render-pipeline/scripts/measure_reference.py --image reference.png --palette 5 --probe 90,265
.venv/bin/python .claude/skills/decodex-render-pipeline/scripts/measure_reference.py --image reference.png --box 60,90,600,230 --background "#043673" --tolerance 30
```

Arguments:

- `--image` (required) — the reference image.
- `--palette` — top N colors by area after quantizing, each with hex and share %. Default `8`.
- `--probe X,Y` (repeatable) — hex of the pixel at that point.
- `--box X0,Y0,X1,Y1` (repeatable) — bounding box of the pixels inside that region that differ
  from the background, in px and as % of the canvas (left/right/width of its width,
  top/bottom/height of its height). `right`/`bottom` are exclusive, so `width = right - left`.
- `--background` — background hex for `--box`. Default: the most common pixel color.
- `--tolerance` — max per-channel difference (0–255) still counted as background. Default `40`.

Anti-aliased edges can shift a box by a pixel or two; lower `--tolerance` to include them, raise
it to ignore them.

## Installation

Install into a virtual environment at the project root, never into the system Python: Homebrew
and recent macOS Python builds refuse a global `pip install` (PEP 668), and forcing it can break
the user's Python. `.venv` is already ignored by git.

```
python3 -m venv .venv
.venv/bin/pip install playwright Pillow
.venv/bin/python -m playwright install chromium
```

Run every script in this skill with `.venv/bin/python` from the project root, not with `python`
or `python3`. Chromium is installed once per machine and shared by every project.
