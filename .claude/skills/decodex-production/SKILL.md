---
name: decodex-production
description: Producing brand pieces from a saved Decodex framework, one piece at a time as HTML exported to an image, with inputs, a render preflight, review and approval. Use when the user chose to create a piece and the brand is ready to produce.
compatibility: Requires the decodex-brand MCP connection and the decodex-render-pipeline .venv (Python 3.9+, Playwright with Chromium, Pillow).
metadata:
  version: "0.1.0"
---

# Decodex production

Follow the reply format of `decodex-workflow` and the way of talking in the root `CLAUDE.md`.

Rules that hold for every piece:

- One piece at a time, built as HTML, never SVG. Approve the first size before adding sizes or
  variants.
- Never edit an exported image. If something is wrong, fix the HTML and render again.
- Every color, font and tone rule in a piece comes from the brand. A value the brand does not
  have is asked, never invented.
- A Maker never changes brand rules. If a Codifier asks for mass production, say it belongs to
  the Maker role and ask how they want to proceed.

Steps:

- **B1 Brand and framework.** Silent: `get_brand_setup_status`. Producing with an empty brand is
  forbidden (the pieces would be generic), so when something is missing, stop here:
  - Base missing (colors, fonts, logos): a Codifier, an administrator, or a person whose role is
    not stated hears "Esta marca aún no tiene su base (colores, tipografías, logos). ¿La
    codificamos primero?", asked with the popup, and on yes goes to `decodex-setup`.
  - Only frameworks missing (`list_frameworks` shows none): the same people hear "Esta marca aún
    no tiene plantillas guardadas. ¿Las armamos primero?", with the same popup.
  - A Maker, in either case, hears "Esta marca aún no está lista para producir. Pídele a quien
    la codifica que la complete." and nothing is produced.

  Otherwise ask which framework they want among the ones `list_frameworks` shows, and read it
  with `get_framework`. Ask: 1) describe the piece,
  2) the data is in a spreadsheet, 3) repeat a previous one (`search_piece_learnings`). A spreadsheet is only a column contract (columns map
  1:1 to the framework's dynamic elements, plus a variant column): produce its first row as one
  piece and say plainly that batch production is not available yet.
- **B2 Inputs and preflight.** Decodex is the only source of inputs (logos, images, fonts,
  colors, tone): never look for one on the person's computer, never ask where it is saved and
  never copy one from a local path. Framework from `get_framework`; colors, fonts, tokens and
  tone from `get_brand_colors`, `get_brand_fonts`, `get_foundations` and `get_brand_voice`
  (Google fonts can be linked in the HTML; in the HTML use the custom properties exactly as
  `get_foundations` names them); legal or prohibited claims with `ask_brand` before drafting
  copy; the product with `list_products`; logo, images and uploaded font files: find them with
  `search_assets`, `list_assets` or `get_brand_fonts`, then, for every one the piece uses, verify
  its copy in the assets folder against Decodex with "Local copy" in `decodex-asset-upload`
  (missing or different hash: download it again). Use only files verified that way; never
  recreate a logo, never transcribe base64 and never swap in another font without saying so. If
  an input is missing in Decodex, say it is missing and offer to upload it with
  `decodex-asset-upload` (for example "Esta tipografía no está en Decodex. ¿La subimos?"); a
  Maker who cannot upload asks the person who codifies the brand. Before the first render check that the
  project's `.venv` has Playwright, Pillow and Chromium (see "Installation" in
  `decodex-render-pipeline`). If something is missing, say it in plain words and ask permission
  before installing. If the render scripts fail for any reason, stop and tell the user. Never
  copy, rewrite or recreate `export_piece.py` or any other rendering script, in any folder, and
  never render with a different tool.
- **B3 Plan.** State brand, framework and size. Options: 1) build the first piece
  (recommended), 2) change the data first.
- **B4 Build and check.** Save the HTML next to its output in
  `content/<N>-<project>/<size>/`; N is the next free number (look at the folders already in
  `content/`) and is never reused. Before rendering, check every color in the HTML (hex, rgb,
  gradients, overlays) against `get_brand_colors` and `get_foundations`. A color that is not
  there is a gap: stop, say it in plain words and ask: 1) use one of the brand's colors (list
  them), 2) ask a Codifier to add it. Never invent a background. Render with
  `decodex-render-pipeline`, then look at the exported image yourself: nothing cut off or
  overflowing. If text does not fit, prefer more lines over shrinking it. Only claim checks you
  actually ran.
- **B5 Review.** Open the piece with the system viewer and ask: 1) correct, 2) change a text,
  price or image, 3) change the campaign look. Only after approval offer another size.
- **B6 Close.** PNG, JPEG or WebP only; no video yet. If the designer taught something,
  `save_piece_learning`.
