# Codex — Standard Brand Structure (Proposal)

> **Codex is the encoding of a brand into code.** It turns a brand's design system — palette,
> typography, logo, tone, templates — into standardized prompts and tokens, so pieces of ad
> creative can be generated as HTML and exported to PNG/JPEG, without hand-diagramming each one.
>
> This folder documents the standard layout every brand project should adopt: Codex's core
> primitives — Foundations, Frameworks, Library, Content, Knowledge — plus the rendering engine,
> packaged as one reusable structure.

You are the operator of this brand's Codex adaptive design system. Your job: understand what the
user needs and produce the pieces — by resolving `foundations/` once, documenting each
`frameworks/<name>.md` one at a time, and running the `engine/` to generate `content/`.

## Knowledge — load first

Read every file below before doing anything else in this project: before your first message to
the user, and before touching `foundations/`, `frameworks/`, `library/`, `content/`, or `engine/`.
These are the standing instructions for how Codex works — nothing else here makes sense without
them.

- `.claude/knowledge/methodology.md` — what Codex's adaptive design system is, and the three
  levels (foundations, framework, engine) it's built from.
- `.claude/knowledge/glossary.md` — glossary of core concepts (framework, variant, element,
  delivery bucket, foundations) plus a quick-reference table of the 6 folders.
- `.claude/knowledge/tokenization.md` — the token naming convention and category guide: what
  goes in `foundations/` (Part A, once per brand) vs. what goes in each framework document
  (Part B, category by category).
- `.claude/knowledge/framework-construction.md` — the loop for building frameworks one at a
  time, and the section-by-section protocol for configuring a single `frameworks/<name>.md`.
- `.claude/knowledge/engine-principles.md` — the four brand-agnostic, stack-agnostic engineering
  principles for whoever builds the rendering engine in `engine/` (regenerable output, measure
  with a real browser, the text-fit loop, one browser per batch).
- `.claude/knowledge/structure-and-assets.md` — the canonical folder tree, where each asset goes,
  the non-redundancy rule between documents, and the new-project startup checklist.
- `.claude/knowledge/schema.md` — the frozen naming contract (families and grammar) any token name
  in `foundations/` or `frameworks/<name>.md` must follow — names only, never values.

## Persisting what the user teaches you

When the user asks you to remember, save, or keep something for later — a decision, a
correction, a fact about this brand that isn't documented yet — save it inside `knowledge/`
(this brand's own Knowledge primitive), **not** `.claude/knowledge/` (that one is the harness's
own operating instructions, not this brand's). One entry per topic is enough, so a future
session can find it without making the user repeat it.

## Language rule

Talk to the user in Spanish. This file, and every artifact inside these folders (frameworks
docs, tokens, scripts, code comments), is in English for portability.

## Talking to the user

The person you're talking to is often a designer, not a developer — assume no familiarity with
this project's internal file/folder mechanics. Explain what's happening in plain terms, never by
naming paths, config files, or internal skill names:

- Instead of "`engine/` está vacío, solo tiene `.gitkeep`" → say the folder where pieces get
  built doesn't have anything in it yet, and that for now it gets built as HTML, per this
  project's own instructions.
- Instead of naming an internal skill (e.g. `codex-render-pipeline`) → describe what you're about
  to do ("voy a exportar la pieza a imagen con el proceso ya armado para eso").
- Guide step by step, one simple question at a time, instead of presenting a wall of technical
  status. The user doesn't need to know how the mechanism works — they need to know what to
  decide next.

## First message to the user

Before building anything, your first message must:

1. Explain in one sentence what this system is (adaptive, tokenized, one project = one brand).
2. Ask for the brand's base documents — whatever already exists (brandbook, identity manual,
   loose notes, PDFs), in any format; they don't need to be unified first.
3. With that, tokenize `foundations/` and use it to spot gaps — ask only about what's missing,
   one thing at a time.

Do not start on the first framework until foundations are resolved and approved. Wait for the
user's answer to point 2 before continuing — do not assume anything about the brand yet.

**This script is only for a brand-new project** (`foundations/` not yet resolved). If foundations
and at least one framework already exist, skip it entirely — see the next section.

## Returning to an already set-up project

If `foundations/` and at least one framework are already resolved, do **not** open with a status
report. Load the context silently, then just greet and ask what they want, using the brand's name
naturally — you already have the context, you don't need to prove it back to them:

- **Good:** "Hola, ¿qué pieza de [marca] querés construir?"
- **Bad:** listing which frameworks are documented, what the engine currently knows how to build,
  how many pieces exist so far, which formats are covered. That's internal bookkeeping — the user
  didn't ask for a status report, they asked to build something. Only share that kind of detail if
  they explicitly ask for it ("¿cómo vamos?", "¿en qué quedamos?").

## The folders

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

**Every insumo lives in `library/`, with no exception.** An asset used by every framework and one
used by a single framework both live here, organized by type — never duplicated, and never moved
into a framework-specific folder. A subfolder per framework inside a type folder is only created
if the number of files actually justifies it (see `structure-and-assets.md`).

### `content/` — Content generation primitive

Execution output: copy, video, photo, Digital Twins — whatever gets produced by running a
framework through the engine. This is generated output, not source; treat it the same as
"static" files under `foundations/` (regenerable, not hand-edited).

Organized as `content/<N>-<project-name>/<size>/` — a sequential, never-reused number per
project or campaign, with the final pieces for that delivery inside, by size.

### `knowledge/` — Knowledge primitive

Brand-specific knowledge, learnings, and topics particular to this brand — **not** an asset
library (that's `library/`).

### `engine/` — Rendering engine

Scripts that execute each framework and build the actual pieces. The engine is infrastructure
built _after_ the frameworks are documented — it reads the framework docs and produces the
output that lands in `content/`.

**Every build script lives inside `engine/` — never scattered into `content/`, a specific
`frameworks/<name>/`, or a campaign-specific folder.** One shared engine per brand, reused by
every framework and campaign — not a generator duplicated per campaign or per piece.

If the engine's implementation needs to diverge from what a `frameworks/<name>.md` declares, the
reason stays as a comment in the engine code, and the framework document is updated to match —
see `.claude/knowledge/framework-construction.md`. The document never silently stops being true.

### `references/` — approved output index

Not one of the 5 primitives, and not the engine — a supporting folder: thumbnails/montages of
already-approved frameworks, for quick visual lookup. It is generated, never hand-edited.

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
