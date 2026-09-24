---
name: codex-legacy-migration
description: Migrate a legacy, unstructured Codex brand implementation (foundations/frameworks/assets scattered ad hoc, possibly with old generator code) into this project's standard harness structure (foundations/, frameworks/, resources/, content/, knowledge/, engine/, references/). Use when a brand already has a Codex-style implementation that predates this structure and needs to be brought in.
license: See repository LICENSE
compatibility: Claude Code / Agent Skills-compatible runtimes
metadata:
  version: "0.1.0"
---

# Codex Legacy Migration

Generalized from two complete migrations done under this structure. Follow this as a checklist,
not a script — each step still requires judgment, and every "doesn't fit" case gets flagged, never
forced or invented.

## The one rule everything else follows from

**The source of truth is always the knowledge — foundations and framework specs — never the
generator code.** Never read, copy, port, or "take inspiration from" the legacy brand's build
scripts / generator code, at any step of this migration. If a legacy engine exists, it stays
untouched in the legacy location. The new `engine/` gets generated later, from the migrated
foundations + frameworks, in a separate step outside this skill's scope.

Everything else below exists to protect that rule.

## Step 1 — Locate and read the legacy foundations source(s)

A brand may have one foundations document, or several (a base doc, a design-system doc, a rules
doc, a structured data file). Read the text/data sources first — a PDF is the *original* source
those were written from, not a shortcut around them; only open one if a category from Step 2 comes
up genuinely empty after reading everything else.

**If a source has a version changelog** (a running log of corrections, several hundred lines or
more): don't read it front-to-back on a first pass. Locate the current/final state sections first
(often near the end, after the changelog). Come back to the changelog only to resolve a specific
ambiguity, and search for it — don't ingest the whole thing by default. It's a legitimate,
valuable source (real corrections, "derived vs. confirmed" flags) — just an expensive one to read
wholesale.

## Step 2 — Adapt into the four `foundations/` files

Split the legacy foundations into `foundations/COLORS.md` (A1), `FONTS.md` (A2), `LOGOS.md` (A3)
and `COPYS.md` (A4), each in the file format defined in `tokenization.md` Part A, with names per
`schema.md`'s grammar. Create only the files the legacy source actually has information for — a
scope with nothing in the source gets no file (it's a gap, logged in Step 6).

Then create `foundations/BRAND.md`, the foundations index, from the files you just migrated
(shape: `tokenization.md` Part A): brand name and description, the status and one-line summary of
each of the four files (a scope with no file is `not created yet`), the open `null # gap:` tokens,
and the `resources/` folders that hold the brand's files — update it again after Step 3 if the
resource pointers change. It indexes the four files; it never restates a value from them.

- **If something doesn't fit any of the four scopes cleanly** (a named set of role-combinations, a
  single decorative asset's own slot interface, anything else that's brand-wide but isn't a
  palette/typography/logo/tone fact): document it anyway, under an explicit ad hoc heading in the
  prose part of the closest-scope file, marked as a gap. Never force it into a token family it
  doesn't belong to, and never invent a new formal category or file on your own — that's a
  decision for the project's `tokenization.md`/`schema.md`, not for one migration.
- **Check that A4 (tone/legal, `COPYS.md`) actually exists** before concluding it's missing — it
  may live in a different file than expected (an operating guide, not the foundations doc itself).
- **Watch for filename drift**: the foundations source may name asset files that don't match what
  actually shipped on disk (typos, renamed files, a changed separator). Use the real, on-disk
  filenames in the migrated `font.file.*` / `logo.*` tokens and in `resources/`; flag the mismatch
  in prose. Don't silently "correct" the source, and don't silently use the wrong name either.
- Don't copy a raw data file into the migrated doc (or into `resources/`) if its content is already
  fully absorbed into a table you just wrote — that's pure duplication, not a second source.

## Step 3 — Copy real assets into `resources/`, organized by type

Inspect what's actually inside each source asset folder before deciding where it goes — don't
infer the category from the source folder's own name. Organize by type into the existing `resources/`
subfolders (`logos/`, `images/`, `videos/`, `icons/`, `sounds/`, `fonts/`).

Some assets won't fit any existing subfolder cleanly (reusable design-component templates, fixed
graphic elements that are closer to framework building blocks than plain insumos). Place them in
the closest existing category and say so explicitly in your report — that's a judgment call, not a
new rule. Don't invent a new `resources/` subfolder for a one-off case; only propose one if the same
kind of asset shows up again in a third brand.

## Step 4 — For each framework, check whether a written spec already exists

**If yes (a real `.md`/spec document exists):** this is a migration. Read it fully, adapt it into
`frameworks/<name>.md` per `tokenization.md`'s B0-B8, and cross-check it against any documented
corrections (a changelog, a rules doc) to mark what's actually verified vs. carried over as
declared. If the legacy project also has a working legacy engine for this framework, do **not**
open it to "double check" — the written spec (plus any changelog) is the knowledge source; the
engine is not, per the one rule above.

**If no (only raw structural assets exist — no prose spec at all): this is a reconstruction, not a
migration.** This is the SVG scenario, but it generalizes to any case where a framework was only
ever built directly into a design/structure file, never written up. Treat that structural source
(SVG, or an equivalent structured design export) the same way `framework-construction.md` treats
a structured design file such as Figma — it gives you real geometry, not intent. Concretely:

- Read the structural files as text/XML (viewBox, coordinates, real measurements) to get exact
  geometry — this is a design source, not code, even though it's file-based like the generator is.
  It is not covered by the one rule above; the generator script sitting next to it still is.
- Cross-reference any changelog/decision-log for facts already confirmed about that specific
  framework (selection rules between variants, values already marked "derived" vs. "confirmed")
  instead of re-deriving everything from geometry alone.
- **Preserve "derived, not verified" labels exactly as the source marks them.** Writing something
  into a cleaner, better-organized document does not make it more confirmed than it was. If the
  source says a value was estimated and never checked against a real design file, say that in the
  new document too.
- Flag real contradictions found between layers as you go (e.g., a component's actual declared
  font in its source file vs. what foundations assigns to that same element) — document both
  sides and the conflict, never silently pick one.
- State explicitly which states/variants you actually measured (e.g., only the base state of a
  multi-variant component) vs. which you're extrapolating — don't imply full coverage you don't
  have.

Either way, note whether the resulting document leaves anything for later at a size/variant level
you didn't reach — an incomplete framework document is expected mid-migration; a silently
overconfident one is not.

## Step 5 — Copy reference images

Into `references/<framework>/`. If none exist for a given framework, say so — don't fabricate a
placeholder.

## Step 6 — Log every unresolved gap explicitly

A gap is a normal outcome of this process, not a failure to hide. Leave it stated in the relevant
document (foundations or the framework doc) or in the project's own `research`/discoveries record
if one exists — never invent a plausible-sounding value to close it quietly.

## What this skill does not do

- It does not touch, read, or generate any engine/build code — see the one rule above.
- It does not decide new `tokenization.md`/`schema.md` categories on its own — it flags candidates.
- It does not validate the result against a QA process — that's a separate, not-yet-built concern
  (see this project's own discoveries log if one exists).
