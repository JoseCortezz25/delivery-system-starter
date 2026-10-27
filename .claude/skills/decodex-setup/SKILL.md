---
name: decodex-setup
description: Step-by-step brand setup in Decodex (colors, fonts, logo, tone, frameworks, test piece), with the right tool for each item and the order it must follow. Use when the user chose to configure the brand or when setup status shows gaps.
compatibility: Requires the decodex-brand MCP connection with the configure permission.
metadata:
  version: "0.1.0"
---

# Decodex setup

Follow the reply format of `decodex-workflow` and the way of talking in the root `CLAUDE.md`.
Before each question call `get_brand_setup_status` and ask only about the first gap. It reports
logo, fonts, colors, tone and frameworks as complete, in progress (a logo uploaded but not
ready yet: remind the user to finish the upload; `list_assets` shows the link) or not started. Do not ask what a
color is for: save what they give you and let each tool's reply tell you what is missing.

- **A1 Brand.** Confirm it with `get_brand`. Wrong brand: `switch_brand` if available.
  Creating a brand is an administrator task; say so, do not attempt it.
- **A2 Foundations.** Ask how they deliver: 1) values typed in chat, 2) files (logos, fonts,
  images), 3) brand documents or a reference image. Offer a Figma link only when a Figma tool
  is connected. Save each item with its tool:
  - Colors: `set_brand_color` (name, hex, primary or secondary).
  - Fonts, logos, images and any other file: follow `decodex-asset-upload` ("Fonts" for fonts).
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
- **A3 Frameworks.** See what is already saved with `list_frameworks`, then ask which piece to
  lay out next (feed 1:1, story 9:16, multi-format banner). One framework at a time, as HTML,
  following `.claude/knowledge/framework-construction.md` for the full protocol. In short:
  start from Figma only when a Figma tool is connected, otherwise from a reference image
  (measured, not eyeballed); check the reference colors and font weights against what is saved
  (its color and font slots point to saved colors and fonts, so those must exist first); approve
  section by section; render the test piece (A4); after approval save with `add_framework` and
  verify with `list_frameworks` and `get_framework`.
- **A4 Test piece.** Render it with `decodex-render-pipeline` and open it. Options: 1) approve,
  2) adjust sizes, spacing or logo. Approve the first size before adding sizes or variants.
- **A5 Close.** When setup status shows no gaps and at least one framework is approved and
  saved, ask: 1) add another framework, 2) produce a piece (then invoke `decodex-production`).
  There is no publish step; what is saved is already live.
