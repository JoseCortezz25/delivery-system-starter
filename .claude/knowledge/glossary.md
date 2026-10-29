# Glossary

## Core concepts

| Concept | What it is | Generic example |
|---|---|---|
| **Framework** | A reusable visual structure, documented in its own `frameworks/<name>.md` with its complete adaptive system | "Product framework": centered object + logo + text below, "product" image mode, its own text limits |
| **Variant** | A variation of components over the SAME composition — never a different layout | "Offer" variant (with price) vs. "Invitation" variant (message only), on the same structure; or "berry" vs. "mango" variant (same layout, different color/product) |
| **Element** | Each piece that makes up a framework — text, image, shape, or empty space — whether dynamic or fixed | Headline (dynamic), logo (fixed), platform CTA zone (fixed, empty) |
| **Delivery bucket** | A group of sizes requested together because they go to the same channel | "Social" (9:16, 1:1) vs. "Display" (banners of several sizes) |
| **Foundations** | The only thing truly shared across all of this brand's frameworks | base palette, logo, base typography, tone, legal |
| **Slot / hueco** | The position inside a framework where an atom or molecule goes | the headline slot, the logo slot |
| **Atom / molecule / component** | Atom is the smallest unit; a molecule can contain several atoms and/or molecules | a color swatch (atom), a price tag combining a number + a label (molecule) |
| **Adaptive design** | The same framework (piece) reflowed into different formats (1:1, 9:16, 16:9, etc.) and channels, without changing its identity — only its slots' sizes, positions, and text scaling adapt per format | one framework rendered at 1:1 and at 9:16 |
| **Digital Twin** | Future concept: a 3D-recontextualized product image (not blocking today) | — |

## Folder structure

Quick reference — see the root `CLAUDE.md` for the full description of each folder.

| Folder | Primitive | Meaning |
|---|---|---|
| `foundations/` | Foundations | Shared brand layer, tokenized once per brand: palette, typography, logo, tone, legal. Saved in Decodex; this folder keeps what its tools don't cover yet. |
| `frameworks/` | Frameworks | One document per framework (`frameworks/<name>.md`): slots, intent, variants, measurements. The local working draft while it's built; the approved version lives in Decodex (`add_framework`, read with `get_framework`). |
| `library/` | Librería de insumos | Raw brand assets: logos, images, videos, icons, sounds, fonts. Uploaded to Decodex (`request_asset_upload`) first, never saved here first. |
| `content/` | Content generation | Generated output — copy, video, photo, Digital Twins — produced by running a framework through the engine. |
| `engine/` | Rendering engine | Scripts that read the framework docs and produce the pieces that land in `content/`. |

Note: this file lives under `.claude/knowledge/` — harness-level knowledge about how Decodex itself
works, available to any AI operating this project. Brand knowledge (the Knowledge **primitive**)
has no local folder: it lives in Decodex — brand facts with `add_knowledge`, designer learnings
with `save_piece_learning`.
