# Figma Extraction

How to use the brand's Figma files as an input (insumo) for `foundations/` and `frameworks/`.
Figma is **one source among several** — a complement that brings more accurate data (real
geometry and values) to what the other sources already give, never the only source and never a
source of truth by itself: whatever comes out of it is organized, named, and confirmed with the
brand expert before it is written anywhere.

**Figma is optional.** Use this only when the user has Figma material for the brand. Never ask
a user without it to adopt Figma, and never treat its absence as a Setup gap — brandbooks, PDFs,
reference pieces, images and descriptions are equally valid inputs, and are combined with Figma
when both exist (see step 0 of `framework-construction.md`).

## Access — local Figma MCP server

The harness connects to the **Figma desktop app** through its local MCP server
(`figma-desktop` in `.mcp.json`, `http://127.0.0.1:3845/mcp`). Nothing goes through a remote API
or a token: the agent only sees what the user has open in their own Figma app.

Prerequisites (the user does this once; explain it in plain terms, step by step):

1. Figma desktop app installed, updated, and logged in.
2. Open the design file, switch to Dev Mode (Shift+D).
3. In the inspect panel, under "MCP server", click "Enable desktop MCP server".
4. Restart the agent session if the server was enabled after it started.

If the server doesn't respond, tell the user Figma isn't connected yet, walk them through the
steps above, and — if they can't enable it — continue with the other sources available (see step 0 of
`framework-construction.md`). Never guess what the file contains.

### Pointing at a node

The tools work on the **current selection** in Figma, or on a node the user shares as a link
(`...?node-id=12-345` → node id `12:345`). Ask the user to select (or link) one frame at a time —
the one that matters for the current step. Never crawl a whole file.

## What each tool gives, and where it goes

| Tool | What it gives | Feeds | Rule |
|---|---|---|---|
| `get_variable_defs` | Variables and styles used by the selection (colors, typography, spacing, radii) | `foundations/COLORS.md`, `foundations/FONTS.md` (Part A) | Figma names are **not** token names: map each value to the `schema.md` families and confirm the mapping with the user |
| `get_metadata` | Layer tree: names, types, ids, position and size of each layer | Framework elements (B3) and exact measurements per size (B6) | Figma gives position, not intent — confirm what each layer is before documenting it |
| `get_design_context` | Styles, layout, text content, and asset references of the selection | Framework elements, text behavior (B5), image mode (B2) | Its generated code is reference only — never copy it into `engine/` (construction is HTML built from tokens) |
| `get_screenshot` | Rendered image of the selection | Visual check while documenting a framework | Used to compare, not stored as an approved reference (`references/` only holds approved output) |

Other tools the server exposes (Code Connect, design-system rules, FigJam) are not part of this
flow; don't use them unless the user asks.

## Assets

Images, logos, icons, and other raw files that come out of Figma (e.g. asset URLs returned by
`get_design_context`) are downloaded into `resources/<type>/` per `structure-and-assets.md` —
never into a framework folder, never duplicated. Logo **usage rules** are still defined by the
user, not inferred from how the file uses the logo.

## Guardrails

- **Tokens first.** A Figma hex or font size becomes a token only after it's named and
  confirmed; a value used once in a mockup is not automatically a brand token.
- **Conflicts are asked.** If Figma disagrees with the brandbook, another Figma frame, or an
  existing foundations file, stop and ask which one wins. Record the decision in `knowledge/`.
- **One frame at a time**, following the framework loop in `framework-construction.md`. Each
  size extracted from Figma is reviewed and approved before the next.
- **Missing isn't zero.** If a value isn't in the file (e.g. no variable for a color, text with
  no style), it's a gap to ask about — never filled with the raw number as if it were defined.
