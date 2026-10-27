# Rules

Conceptual rules for Decodex's way of working — how any brand project using this structure is
meant to be built, independent of any specific brand. Framework-specific behavior
(text scaling, image fitting, exact measurements per size, etc.) is **not** listed here — it
belongs inside each `frameworks/<name>.md` document itself.

## Golden rule

> If a value is not in a token or in a framework document, it is not invented. It is asked.

## Non-negotiable rules

1. **One project = one brand.** This method applies once per brand — two brands never coexist,
   and never share foundations, in the same project. Never bring in tokens from another project.
2. **The adaptive system is not a separate stage — it lives inside each framework.** Only what is
   truly shared across the whole brand (base palette, logo, typography, tone, legal) is resolved
   once, at the start, per brand.
3. **Everything else is documented framework by framework, one at a time.** Elements, variants,
   text rules, exact measurements, and sizes are never generalized upward or drafted for several
   frameworks at once — each one is configured on its own, with continuous verification before
   approving it, before moving to the next.
4. **Each framework is a single document.** The approved version is saved in Decodex with
   `add_framework`; `frameworks/<name>.md` is its local working copy (see
   `framework-construction.md`). It is written at a high level of detail — a specification, for
   someone to implement later. No code lives at this layer.
5. **Names follow the established token/role family convention.** Never an invented, loose name
   created in the moment.
6. **Approval before scaling.** The first size's document is shown and approved before adding
   further variants or sizes.
7. **Save approved decisions to Decodex as you go.** As foundations and frameworks get approved,
   they are saved with their Decodex tool, and a brand fact no tool covers is saved with
   `add_knowledge` — so a future session starts from what was already resolved, instead of
   re-reading the method package from scratch. The project's `CLAUDE.md` describes how the
   project works; it never holds brand values.
8. **Each fact lives in exactly one place.** Decodex is the source of truth for brand data:
   foundations, frameworks and asset files. Locally, `foundations/` keeps only what the tools
   don't cover yet; framework-wide facts live in that framework's document; a single size's
   measurements live in that size's row; the folder structure itself lives in
   `.claude/knowledge/structure-and-assets.md`. The files in `library/` are local copies of the
   assets stored in Decodex, organized by type: one copy per asset, never duplicated across
   folders, never moved into a framework-specific folder.
9. **Construction is HTML — never SVG.** SVG was tried and failed: "El SVG no sirvió: movía
   textos y posiciones, no es manipulable, no incrusta imágenes bien, no vale para piezas
   completas ni video." Every engine in this project renders a piece as HTML and exports it to a
   raster image (see `.claude/knowledge/engine-principles.md`) — never by manipulating an SVG
   template directly, no matter how the original brand's legacy tooling worked.
