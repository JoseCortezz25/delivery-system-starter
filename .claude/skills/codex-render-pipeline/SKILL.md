---
name: codex-render-pipeline
description: Deterministic, pre-built scripts to export an HTML piece to a raster image (PNG/JPEG/WebP) with an exact pixel clip, and to scale/resize an existing image. Use this skill any time a piece needs to be rendered to an image file or an image needs to be resized — invoke these scripts instead of writing new rendering or resizing code from scratch.
compatibility: Requires Python 3.9+, Playwright (with Chromium installed), and Pillow.
metadata:
  version: "0.1.0"
---

# Codex Render Pipeline

## Why this skill exists

This project's own engine analysis (`analysis/patrones-motor-hit.md` §3.1) found a real, verified
bug pattern in the HIT brand's rendering engine: its shared `render_save()` only ever supported a
square clip (`{"width": size, "height": size}`), so every non-square builder (9:16 stories,
banners) ended up hand-rolling its own near-identical screenshot function. That is exactly the
class of improvised, one-off code this skill exists to prevent — for any brand, not just HIT.

**Do not write your own HTML→image rendering code or your own image-resizing code.** Use the
scripts below instead. They are brand-agnostic — they know nothing about any brand's tokens,
colors, or fonts — and are meant to be the one shared tool every framework/builder calls.

## `scripts/export_piece.py` — render an HTML piece to an image

Renders an HTML file (or an inline HTML string) with headless Chromium and captures an **exact**
`width x height` clip — never assumes a square canvas.

```
python scripts/export_piece.py --html piece.html --width 1080 --height 1920 --output out.png
python scripts/export_piece.py --html-string "<html>...</html>" --width 300 --height 250 --output out.jpg --format jpeg
python scripts/export_piece.py --html piece.html --width 1080 --height 1920 --output out.png --scale 2
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
python scripts/scale_image.py --input piece.png --output piece_small.png --width 540
python scripts/scale_image.py --input piece.png --output piece_small.png --height 960
python scripts/scale_image.py --input piece.png --output piece_2x.png --scale 2.0
python scripts/scale_image.py --input piece.png --output thumb.jpg --width 300 --height 300
```

Arguments:

- `--input`, `--output` (required).
- `--width` and/or `--height` — if only one is given, aspect ratio is preserved. Mutually
  exclusive with `--scale`.
- `--scale` — uniform factor (e.g. `0.5`, `2.0`). Mutually exclusive with `--width`/`--height`.
- `--format` — forces an output format; otherwise inferred from `--output`'s extension.
- `--quality` — 1–100, applies to lossy formats only. Default `90`.

Uses `Image.LANCZOS` resampling — the same resampling this ecosystem's own engine already uses for
downscaled previews (`hit_core.save_preview`).

## Installation

```
pip install playwright Pillow
python -m playwright install chromium
```
