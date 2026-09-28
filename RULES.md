# Rules

Conceptual rules for Codex's way of working — how any brand project using this structure is
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
4. **Each framework has one canonical specification.** The result is always `frameworks/<name>.md`,
   written at a high level of detail for later implementation. A generated, geometry-only Figma
   anatomy may be stored as `frameworks/templates/<name>.html` and indexed in `frameworks/README.md`;
   it is a derived companion, not a second specification or production implementation. Regenerate
   it from Figma rather than hand-editing it.
5. **Names follow the established token/role family convention.** Never an invented, loose name
   created in the moment.
6. **Approval before scaling.** The first size's document is shown and approved before adding
   further variants or sizes.
7. **Organize what the user provides into the right files as you go — never into the harness.**
   During Setup, every piece of information is written, by scope, into the file that owns it:
   the matching `foundations/` file (creating it on first info), `frameworks/<name>.md`,
   `knowledge/` for brand facts and decisions, and raw assets into `resources/`. Keep
   `foundations/BRAND.md` updated as the index, so a future session starts from what was already
   resolved (reading `BRAND.md` first) instead of re-asking. `CLAUDE.md`, `RULES.md` and
   `.claude/` are the harness — never written to from inside the project (see rule 10).
8. **Each authored fact lives in exactly one place.** Foundations facts live in the one `foundations/` file
   that owns their scope (`COLORS.md`, `FONTS.md`, `LOGOS.md`, `COPYS.md`) — `BRAND.md` only
   indexes them, never restates a value;
   framework-wide facts live in that framework's document; a single size's measurements live in
   that size's row. Generated anatomy HTML is a derived Figma snapshot, not an independently
   maintained source of truth. The folder structure itself lives in
   `.claude/knowledge/structure-and-assets.md`. Assets always live in `resources/`, organized by
   type — never duplicated, never moved into a framework-specific folder.
9. **Construction is HTML — never SVG.** SVG was tried and failed: "El SVG no sirvió: movía
   textos y posiciones, no es manipulable, no incrusta imágenes bien, no vale para piezas
   completas ni video." Every engine in this project renders a piece as HTML and exports it to a
   raster image (see `.claude/knowledge/engine-principles.md`) — never by manipulating an SVG
   template directly, no matter how the original brand's legacy tooling worked.
10. **The harness is read-only; the brand folders are the agent's workspace; base folders are
    never deleted.** Working inside this project, the AI never creates, edits, deletes, or moves
    `CLAUDE.md`, `RULES.md`, `.mcp.json`, `.gitignore`, or anything inside `.claude/`. It may
    freely create and edit the documents inside the project folders (e.g. `foundations/*.md`,
    `frameworks/<name>.md`, `knowledge/`) and add and organize files inside `resources/`. It
    never deletes or moves away the base folders (`.claude`, `foundations`, `frameworks`,
    `resources`, `content`, `knowledge`, `engine`, `references`) or any folder inside them —
    deleting a single file inside them is fine. Enforced by `.claude/hooks/protect-claude-dir.sh`
    (edits) and `.claude/hooks/block-protected-delete.sh` (deletions).
