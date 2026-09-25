# Codex Methodology

## What this is

Codex's adaptive design system is a **set of frameworks**, each with its own complete adaptive
configuration (intent, objective, channels, rules, text behavior, image behavior, sizes), built
one at a time on top of a minimal shared brand base.

**One project = one brand, always.** This method applies once per brand. Two brands never
coexist in the same project, and foundations are never shared between different brands — if a
new brand shows up, it's a new project, with its own foundations built from scratch. The only
thing reused from project to project is the method itself (this structure), never one brand's
tokens inside another brand's project.

**The adaptive system is not a layer separate from the frameworks — it lives inside each
framework.** There is no single "adaptive rules" document that applies uniformly to everything.
Each framework behaves differently because it solves a different problem (a product shot vs. an
environment photo, a price offer vs. a brand message), so each one needs its own complete
specification: a `frameworks/<name>.md` document (see `glossary.md` and the root `CLAUDE.md`).

The one thing that IS truly cross-cutting — and is therefore resolved once, before touching any
framework — is the **brand foundations**: the identity that doesn't change no matter which
framework is being built. See `foundations/` — `COLORS.md`, `FONTS.md`, `LOGOS.md`, `COPYS.md`,
indexed by `BRAND.md` (all defined in `tokenization.md` Part A).

## The three levels

1. **Foundations (shared, once per brand):** base brand palette, base typography, logo,
   communication tone, legal boundaries. Tokenized at the start of the project, from whatever the
   brand expert provides, with gaps filled in before moving on.
2. **Framework (configured one at a time, result = a document):** each framework is built from
   every source the brand has for it, combined (reference pieces, descriptions, brandbook, and
   optionally Figma for more accurate geometry) — and is
   configured in detail, section by section, together with the brand expert. The result is
   **a single document, `frameworks/<name>.md`**: intent, objective, channels, color roles, image
   mode, variants, the complete list of elements (dynamic and fixed), typography and text
   scaling, and the exact measurements of every element — spacing, margins, radii, elevations,
   strokes — for every size the framework covers. There is no code at this layer: the document,
   built together with the brand expert, IS the complete specification for that framework.
3. **Rendering engine (technical infrastructure, a separate concern):** the implementation built
   AFTERWARDS, reading these framework documents as the specification. Lives in `engine/` — see
   the root `CLAUDE.md` for how it relates to the other folders.

## Non-negotiable rules

See the root `RULES.md` for the full set.
