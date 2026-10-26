---
name: decodex-setup
description: Step-by-step brand setup in Decodex (colors, fonts, logo, tone, frameworks, test piece), with the right tool for each item and the order it must follow. Use when the user chose to configure the brand or when setup status shows gaps.
---

# Decodex setup

Follow the reply format of `decodex-workflow` and the way of talking in the root `CLAUDE.md`.
Before each question call `get_brand_setup_status` and ask only about the first gap. It reports
logo, fonts, colors and tone as complete, in progress (a logo uploaded but not ready yet: remind
the user to finish the upload; `list_assets` shows the link) or not started. Do not ask what a
color is for: save what they give you and let each tool's reply tell you what is missing.

- **A1 Brand.** Confirm it with `get_brand`. Wrong brand: `switch_brand` if available.
  Creating a brand is an administrator task; say so, do not attempt it.
- **A2 Foundations.** Ask how they deliver: 1) values typed in chat, 2) files (logos, fonts,
  images), 3) brand documents or a reference image. Offer a Figma link only when a Figma tool
  is connected. Save each item with its tool:
  - Colors: `set_brand_color` (name, hex, primary or secondary).
  - Fonts: `add_google_font` (catalog id) first: it is instant. A font file has no direct
    upload route, and `add_brand_font` sends the whole file as text through the conversation,
    which took about 7 minutes in tests. For a font file, say it can take several minutes and
    offer: 1) the closest Google font, 2) wait for the upload. Use `add_brand_font` only after
    a clear yes.
  - Logos and images: `request_asset_upload` (or `request_batch_asset_upload` for two or
    more). Never `add_asset`: like `add_brand_font`, it sends the whole image as text and
    takes minutes. Never guess a path. An image only attached to the conversation is not a
    file: you may read colors from it, but to save it you need one of the two options below.
    Ask with the popup how they want to pass it:
    1. "Te digo dónde está guardado" (recommended). Ask for the folder and the exact file
       name, check that the file exists, copy it into `library/<type>/`, then request the
       link and run curl from that copy in the same step: the link is single use and valid
       for 30 minutes, so never request it before the file is ready. If Desktop asks
       permission to read outside the project folder, tell the user to accept it. Then check
       with `list_assets` that the asset shows as ready. If the file cannot be read or curl
       fails, switch to option 2 without making the user repeat anything.
    2. "Subirlo desde un enlace". Request the link and give it with plain steps: "Abre este
       enlace, toca *Elegir archivo*, selecciona el logo y toca *Subir*. Cuando diga
       *Uploaded*, vuelve aquí". The form picks a file from the computer, not the chat
       attachment. When they say it is done, check with `list_assets` that the asset shows
       as ready.
    Production builds pieces from the local copy in `library/<type>/`: `get_asset` only
    shows the image to you, it cannot hand you the file. Option 2 leaves no local copy, so
    when a piece first needs that logo or image, ask where the file is saved and copy it
    into `library/<type>/` (a copy, no upload).
  - Tone: `set_brand_voice`. Optional basics (timezone, currency, default language):
    `set_brand_core`. Both replace everything on each call, so read what is stored first
    (`get_brand_voice`) and send every field again, or an omitted one is cleared.
  - Facts, legal rules and colorways: `add_knowledge` (text plus a source label). Only the
    labels can be read back (`list_knowledge`), not the text.
  - Products: `save_product`, `update_product`, `list_products`.
  - Tokens with no dedicated tool (spacing, radii): `set_foundation`, only for values the user
    gives you.
  - Deleting (`delete_knowledge`, `delete_product`, `delete_asset`): see "Deleting" in
    `decodex-workflow`. `delete_asset` is for stale or pending uploads only.
- **A3 Frameworks.** Ask which piece to lay out first (feed 1:1, story 9:16, multi-format
  banner). One framework at a time, as HTML. Its color and font slots point to saved colors and
  fonts, so those must exist first. Save with `add_framework` only after approval.
- **A4 Test piece.** Render it with `decodex-render-pipeline` and open it. Options: 1) approve,
  2) adjust sizes, spacing or logo. Approve the first size before adding sizes or variants.
- **A5 Close.** When setup status shows no gaps and at least one framework is approved and
  saved, ask: 1) add another framework, 2) produce a piece (then invoke `decodex-production`).
  There is no publish step; what is saved is already live.
