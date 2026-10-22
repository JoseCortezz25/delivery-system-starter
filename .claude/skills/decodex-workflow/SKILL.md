---
name: decodex-workflow
description: Guided Setup and Production procedure for a Decodex brand project. Router, one structured question per turn asked through the AskUserQuestion popup, Decodex checks at every stage, and the next best action. Use at the start of every session and whenever the user moves between configuring the brand and producing pieces.
---

# Decodex workflow

## Reply format (every turn, in Spanish)

1. **Where we are** — one sentence of plain text: what was just done, or the current stage.
2. **One question, asked with the `AskUserQuestion` popup** with 2-4 options. Never an open
   blank-page question. Put the recommended option first and end its label with
   "(Recomendada)". The popup already offers "Otro" for free text, so never add it yourself.
   Keep the header short (12 characters max).
3. **Next step** — one line of plain text before the popup: "Lo siguiente: ...".

One question per turn: after calling the popup, stop and wait for the answer. Never name
tools, folders or files to the user. If the popup is not available in this client, ask the
same question as a numbered list in plain text and stop.

## Step 0 — Router (silent)

Call `get_brand` and `get_brand_setup_status`. If a call fails, go to "Connection errors".
Greet by the brand's name and ask, with the popup:

1. Configure the brand
2. Produce a piece
3. Review or update what is already saved

Recommend 1 while the brand is not ready to produce, 2 once it is. A brand is ready when setup
status shows no gaps (logo, fonts, colors, tone) **and** at least one framework is saved: the
status does not track frameworks and no tool lists them, so ask the user for the framework's
name and confirm it with `get_framework`. Do not open with a status report.

Roles: the server decides permissions. A Maker never changes brand rules; a Codifier
configures and does not mass-produce. If a tool says the action is not allowed, say so in
plain words, point to their administrator, and never work around it.

## Setup

Before each question call `get_brand_setup_status` and ask only about the first gap.

- **A1 Brand.** Confirm it with `get_brand`. Wrong brand: `switch_brand` if available.
  Creating a brand is an administrator task; say so, do not attempt it.
- **A2 Foundations.** Ask how they deliver: 1) values typed in chat, 2) files (logos, fonts,
  images), 3) brand documents or a reference image. Offer a Figma link only when a Figma tool
  is connected. Save each item with its tool:
  - Colors: `set_brand_color` (name, hex, primary or secondary).
  - Fonts: `add_google_font` (catalog id) or `add_brand_font` (the attached file). Fonts do
    not go through the upload link.
  - Logos and images: `request_asset_upload` + curl, then keep the original in
    `library/<type>/`. Production builds pieces from that local copy: `get_asset` only shows
    the image to you, it cannot hand you the file.
  - Tone: `set_brand_voice`. Optional basics (timezone, currency, default language):
    `set_brand_core`. Both replace everything on each call, so read what is stored first and
    send every field again, or an omitted one is cleared.
- **A3 Frameworks.** Ask which piece to lay out first (feed 1:1, story 9:16, multi-format
  banner). One framework at a time, as HTML. Its color and font slots point to saved colors and
  fonts, so those must exist first. Save with `add_framework` only after approval.
- **A4 Test piece.** Render it with `decodex-render-pipeline` and open it. Options: 1) approve,
  2) adjust sizes, spacing or logo. Approve the first size before adding sizes or variants.
- **A5 Close.** When setup status shows no gaps and at least one framework is approved and
  saved, ask: 1) add another framework, 2) produce a piece. There is no publish step; what is
  saved is already live.

## Order

Setup comes before Production, always. Inside Setup: colors, fonts and logo; then tone; then
frameworks; then the test piece and its approval. Never start a framework while colors, fonts
or logo are missing, and never produce while no framework is saved.

## Production

Rules that hold for every piece:

- One piece at a time, built as HTML, never SVG. Approve the first size before adding sizes or
  variants.
- Never edit an exported image. If something is wrong, fix the HTML and render again.
- A Maker never changes brand rules. If a Codifier asks for mass production, say it belongs to
  the Maker role and ask how they want to proceed.

Steps:

- **B1 Brand and framework.** Silent: `get_brand_setup_status`. If gaps remain, say the brand
  is not ready to produce. Ask which framework they want and confirm it with `get_framework`;
  if it does not exist, say so and offer Setup (Codifier) or their administrator. Ask:
  1) describe the piece, 2) the data is in a spreadsheet, 3) repeat a previous one
  (`search_piece_learnings`). A spreadsheet is only a column contract (columns map 1:1 to the
  framework's dynamic elements, plus a variant column): produce its first row as one piece and
  say plainly that batch production is not available yet.
- **B2 Inputs and preflight.** Framework from `get_framework`; colors and fonts from
  `get_brand_colors` and `get_brand_fonts` (Google fonts can be linked in the HTML); logo and
  images from `library/`. If a needed file is not in `library/`, say so and ask the user for
  it: never recreate a logo and never transcribe base64. Before the first render check that
  Python, Playwright, Pillow and Chromium are installed. If something is missing, say it in
  plain words and ask permission before installing; never write your own rendering code.
- **B3 Plan.** State brand, framework and size. Options: 1) build the first piece
  (recommended), 2) change the data first.
- **B4 Build and check.** Save the HTML next to its output in
  `content/<N>-<project>/<size>/`; N is the next free number and is never reused. Render with
  `decodex-render-pipeline`, then look at the exported image yourself: nothing cut off or
  overflowing. If text does not fit, prefer more lines over shrinking it. Only claim checks you
  actually ran.
- **B5 Review.** Open the piece with the system viewer and ask: 1) correct, 2) change a text,
  price or image, 3) change the campaign look. Only after approval offer another size.
- **B6 Close.** PNG, JPEG or WebP only; no video yet. If the designer taught something,
  `save_piece_learning`.

## Never hardcode a brand value

Every color, font, voice rule and framework value comes from a Decodex read. If one is
missing, go back to the Setup gap; never embed it in a script. Colorways: `add_knowledge`.

## Connection errors

If a tool fails or is unavailable: stop, say it in plain words, do not invent values and do
not save locally instead. Options: 1) retry (log in again), 2) consult only what is already
in the local folders, nothing saved, 3) stop here.

Missing mandatory data (for example fonts): "Falta la tipografía oficial." Options: 1) upload
the font file, 2) use a system font only for this test (not saved to the brand).
