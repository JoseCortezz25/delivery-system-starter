---
name: codex-workflow
description: Defines the mandatory two-stage workflow for operating a Codex brand project — Setup (detect and fill every gap in the brand's knowledge, then close with an approved validation piece) and Execution (produce pieces from the approved knowledge). Use at the start of every session, and whenever deciding what to do next (a new request, new material from the user, or a request that hits something undocumented).
license: See repository LICENSE
compatibility: Claude Code / Agent Skills-compatible runtimes
metadata:
  version: "0.1.0"
---

# Codex Workflow — Setup and Execution

Every session is in exactly one of two stages. Decide which one before your first message, and
re-decide every time the user brings new material or a new request.

## Hard rules

- **Never enter Execution while Setup has open gaps relevant to the requested piece.**
- **Never start Execution for the first time without either** (a) the Setup validation piece
  approved, or (b) a project whose brand knowledge was already complete when the session started.
- The golden rule applies in both stages: a value that isn't in a token or a framework document is
  asked, never invented (`RULES.md`).
- Talk to the user in plain, non-technical Spanish — no paths, folder names, or skill names (see
  "Talking to the user" in `CLAUDE.md`).

## Step 0 — Detect the stage (silently)

Read `foundations/BRAND.md` first if it exists — it's the index of the brand's foundations
(status, open gaps, where the files are) and tells you which foundations files to open. If it
doesn't exist, the project is brand-new, or it predates the index: in the latter case, create it
from the foundations files that exist (shape: `tokenization.md` Part A) before going on.

Then inspect `foundations/`, `frameworks/`, `resources/`, and `knowledge/` against the **Setup
completeness checklist** in `.claude/knowledge/structure-and-assets.md` — that checklist is the
single source for what "complete" means; don't restate it.

- Every item relevant to what the user wants is satisfied → **Execution**.
- Anything relevant is missing or has gaps → **Setup**. This includes partial projects, not only
  empty ones: foundations but no frameworks; frameworks but missing logos, fonts, or images;
  foundations with gaps.

Don't narrate this inspection. It's input for your first message, not the message itself.

## Stage 1 — Setup

### 1. Report what's there and what's missing

In one short message, in plain terms: what the brand already has (e.g. "ya tengo los colores y la
tipografía de la marca") and what's missing (e.g. "me faltan los logos y todavía no hay ninguna
plantilla armada"). No paths, no folder jargon, no checklist dump.

For a brand-new project, also explain in one sentence what this system is (adaptive, tokenized,
one project = one brand).

### 2. Ask for everything they have

Ask the user to hand over everything they have, in any format, unorganized is fine: brandbook,
identity manual, PDFs, loose notes, logos, photos, videos, icons, fonts, sounds, Figma links,
reference pieces. They don't need to sort or unify it — organizing it is your job. Then wait for
their answer; don't assume anything about the brand before it.

### 3. Organize what arrives

Place each thing where it belongs, per `.claude/knowledge/structure-and-assets.md`:

| What arrives | Where it goes | How |
|---|---|---|
| Raw assets (logos, photos, videos, icons, fonts, sounds) | `resources/<type>/` | Inspect each file to decide its type; never duplicate |
| Palette, brand-wide radii/patterns | `foundations/COLORS.md` | Tokenize per `tokenization.md` Part A (A1) and `schema.md` |
| Typography inventory, brand-wide type rules | `foundations/FONTS.md` | Per Part A (A2); font files themselves go to `resources/fonts/` and are referenced by path |
| Logo usage rules | `foundations/LOGOS.md` | Per Part A (A3); only the rules the user defines — logo files go to `resources/logos/` |
| Tone, voice, do/don't, prohibited claims, legal | `foundations/COPYS.md` | Per Part A (A4) |
| Framework material (templates, reference pieces, Figma structures) | `frameworks/<name>.md` | Per `framework-construction.md` — one framework at a time, approved before the next |
| Brand facts, decisions, corrections | `knowledge/` | One entry per topic |

Foundations files are created on first information, not upfront: the first time the user gives
anything for a scope (a color, a font, a logo rule, a tone note), create that file in the format
defined in `tokenization.md` Part A, then keep adding to the right file by scope as more arrives.
A scope with no information yet has no file — that's a gap to ask about in step 4, never a file
to pre-fill.

`foundations/BRAND.md` (the index) is created together with the first foundations file, as soon
as the brand's name / first info is known, and updated after **every** organize pass that creates
or changes a foundations file: its status, one-line summary, open gaps, and `resources/` pointers
(shape: `tokenization.md` Part A). It never restates a value.

Order constraint: foundations are resolved and approved **before** the first framework is started
(`framework-construction.md` precondition). Framework material that arrives early is kept in
`resources/` or noted, not built into a framework yet.

### 4. Ask only for gaps

After organizing, ask only about what's still missing or ambiguous — **one question at a time**,
simplest first. Never fill a gap with a plausible value.

### 5. Keep collecting until the user says they're done

Setup stays open, accepting more material, until the user explicitly says they have nothing more
(e.g. "listo, no tengo más"). Don't close it on your own because the checklist looks complete.

### 6. Close with a validation piece

Once the user has declared they're done, propose one small test: a single piece from one approved
framework, built with the real foundations and resources, rendered and shown for approval (build
and export exactly as in Execution below).

Before proposing it, check that `foundations/BRAND.md` is up to date and lists no open gaps
relevant to the validation piece; if it does, resolve them first (step 4).

- Approved → Setup is closed; move to Execution.
- Something missing or wrong → fix it back in Setup (steps 3-4), then build the test piece again.

## Stage 2 — Execution

Production, following the existing procedure — don't reinvent it:

1. Build the piece as HTML from its `frameworks/<name>.md` and `foundations/`, using the scripts in
   `engine/` (generators that speed up batches) per `.claude/knowledge/engine-principles.md`.
2. Export to PNG/JPEG with the `codex-render-pipeline` skill — never with ad hoc rendering code.
3. Deliver into `content/<N>-<project-name>/<size>/` (new sequential number per project/campaign).
4. Approval before scaling: show the first size/variant before producing more (`RULES.md`).

**Returning to a complete project:** don't open with a status report. Greet using the brand's name
and ask what piece they want (see `CLAUDE.md`).

## Transitions

- **Setup → Execution:** user declared they have nothing more **and** the validation piece is
  approved. (Or: the checklist was already complete at session start.)
- **Execution → Setup (for one gap):** the user brings new material, or asks for something not
  documented — a new framework, a missing asset, an undefined value. Tell them plainly what's
  missing, run Setup steps 2-4 for that gap only (a new framework follows the full
  framework-construction loop and its approval), then return to Execution.
