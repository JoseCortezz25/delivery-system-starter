# Codex — Standard Brand Structure (Proposal)

> **Codex is the encoding of a brand into code.** It turns a brand's design system — palette,
> typography, logo, tone, templates — into standardized prompts and tokens, so pieces of ad
> creative can be generated as HTML and exported to PNG/JPEG, without hand-diagramming each one.
>
> This folder documents the standard layout every brand project should adopt: Codex's core
> primitives — Foundations, Frameworks, Library, Content, Knowledge — plus the rendering engine,
> packaged as one reusable structure.

## Language rule

Talk to the user in Spanish. This file, and every artifact inside these folders (frameworks
docs, tokens, scripts, code comments), is in English for portability.

## The 6 folders

### `foundations/` — Foundations primitive

Shared brand layer, tokenized once per brand: atoms, atom-components, styles, design tokens,
typography, components, molecules.

- **Editable**: token source files, typography scale, color palette, logo rules, tone/legal docs.
  These are the ones a person maintains by hand and are the single source of truth.
- **Static**: anything generated FROM those tokens (compiled style sheets, exported swatches,
  rendered component previews). Never hand-edit static output — regenerate it from the editable
  source instead.

### `frameworks/` — Frameworks primitive

Template system: slots/huecos, one document per framework. Each `frameworks/<name>.md`
documents intent, channels, color roles, image mode, variants, elements (dynamic + fixed), text
scaling, and exact measurements per size. A slot receives an atom or a molecule from
`foundations/`.

### `library/` — Insumos primitive (Librería de insumos)

Brand asset library: logos, brand images, brand videos, sounds, and any other raw brand asset.
Organized by asset type:

- `library/logos/` — brand logo files (all variants: full, mark-only, light/dark, etc.).
- `library/images/` — brand images / photos.
- `library/videos/` — brand videos.
- `library/icons/` — icon sets.
- `library/sounds/` — sound assets.
- `library/fonts/` — brand typeface files.

### `content/` — Content generation primitive

Execution output: copy, video, photo, Digital Twins — whatever gets produced by running a
framework through the engine. This is generated output, not source; treat it the same as
"static" files under `foundations/` (regenerable, not hand-edited).

### `knowledge/` — Knowledge primitive

Brand-specific knowledge, learnings, and topics particular to this brand — **not** an asset
library (that's `library/`).

### `engine/` — Rendering engine

Scripts that execute each framework and build the actual pieces. The engine is infrastructure
built _after_ the frameworks are documented — it reads the framework docs and produces the
output that lands in `content/`.

## Non-negotiable rules

See `RULES.md` for the full set of general technical rules the AI must follow in this project.

## Skills

| Skill | Purpose |
|---|---|
| `codex-render-pipeline` | Deterministic, pre-built scripts to export an HTML piece to a raster image (PNG/JPEG/WebP) with an exact pixel clip, and to scale/resize an existing image. Use any time a piece needs to be rendered to an image file or an image needs to be resized — call these scripts instead of writing new rendering or resizing code from scratch. |

## Key terms

- **Atom / molecule / component** — atom is the smallest unit; a molecule can contain several
  atoms and/or molecules.
- **Slot / hueco** — the position inside a framework where an atom or molecule goes.
- **Framework** — a set of slots / a template that assembles one piece.
- **Adaptive design** — the same framework (piece) reflowed into different formats (1:1, 9:16,
  16:9, etc.) and channels, without changing its identity — only its slots' sizes, positions,
  and text scaling adapt per format.
- **Digital Twin** — future concept: a 3D-recontextualized product image (not blocking now).
