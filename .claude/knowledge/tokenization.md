# Tokenization — Category Guide

Tokenizing means translating every brand decision into a **named value**, so a framework
consumes it by reference ("use the `primary` color") and never by a loose value ("use
`#E4002B`"). This is what makes it possible to switch variant, photo, or framework without
touching the structure.

This guide has two parts, because not everything gets tokenized at the same moment:

- **Part A — Foundations.** Resolved ONCE, before touching any framework. It's what is truly
  shared.
- **Part B — Framework parameters.** NOT filled in here. These are the categories resolved one
  at a time, inside the configuration of each framework — see `framework-construction.md`. They
  are listed here only as a reference of what exists.

If a category doesn't apply to the current brand, it's declared explicitly as "not applicable" —
never silently omitted.

## Naming convention (applies in `foundations/` and in each framework's `.md`)

Every token is named under one of these families. The family is what repeats identically across
any brand; the full name changes depending on what the brand actually has. This is the
vocabulary the written specification uses — and the one any future implementation built from it
should use too (see `engine-principles.md`).

| Family | What it's for | Level |
|---|---|---|
| `color.palette.*` | The raw hex, by name (A1, `foundations/COLORS.md`) — never referenced directly from a framework | Foundations |
| `color.role.*` | The semantic layer a framework does reference (B1) — points to a `color.palette.*`, never to a hex | Framework |
| `font.family.*` / `font.weight.*` / `font.size.*` / `font.tracking.*` / `font.leading.*` | Typography: inventory (A2, `foundations/FONTS.md`) and per-element assignment/scaling (B5) | Foundations + Framework |
| `font.file.*` | Path to a typeface file in `resources/fonts/` (A2) | Foundations |
| `logo.*` | Path to a logo version in `resources/logos/` (A3, `foundations/LOGOS.md`) | Foundations |
| `spacing.safe.*` | Safe margins (e.g. `spacing.safe.top`) | Framework |
| `product.*` / `media.*` | Assets for "product" mode or "photo" mode (B2, B8) | Framework |
| `container.*` / `content.*` | Layout geometry — position, size, anchor (B6) | Framework, per size |
| `cta.safezone.*` | The zone a platform (Meta, etc.) reserves for its own button — the system never draws anything there | Framework |
| `pattern.*` | If the brand has its own decorative motif (e.g. a recurring background icon or texture) — slot names in `foundations/COLORS.md`, per-piece use in the framework | Foundations (slot names) + Framework |
| `radius.*` | Reusable corner radii (e.g. `radius.pill`, `radius.card`) | Foundations (`foundations/COLORS.md`) or Framework, depending on whether it's brand-wide or piece-specific |

If something doesn't fit any family, add a new row to this table — the list isn't closed. But a
new family follows the same grammar as the others: `family.subfamily.detail`, in English, in
lowercase, from most general to most specific (e.g. `color.role.background.primary`, not
`colorRoleBgPrimary` or "background primary color role").

If the brand expert or the designer proposes a name that doesn't respect this grammar, or
something that doesn't fit any existing family well, it isn't accepted as-is just because that's
what was asked: it gets flagged, and the aligned name or family is suggested instead. The same
applies to any other rule in this method that's clearly improvable in the moment — propose the
improvement, don't apply it silently and don't ignore it.

---

## Part A — Foundations (once, shared by every framework)

Foundations is split into four single-responsibility files, one per category below, plus one
index, `BRAND.md`, that summarizes them — its only own facts are the brand's name and short
description. Each foundations fact lives in exactly
one of the four, chosen by scope:

| Category | File | Scope |
|---|---|---|
| A1 | `foundations/COLORS.md` | Base palette + other brand-wide, non-typographic tokens (`radius.*`, foundation-level `pattern.*` slot names) |
| A2 | `foundations/FONTS.md` | Typography inventory, font files, brand-wide typography usage rules |
| A3 | `foundations/LOGOS.md` | Logo files and the logo usage rules the user has defined |
| A4 | `foundations/COPYS.md` | Tone, voice, do/don't examples, prohibited claims and legal boundaries |
| Index | `foundations/BRAND.md` | Brand name + short description, and the status/summary of the four files above — never a token value or rule (see "The foundations index" below) |

**Lifecycle.** None of these files exists in the empty template (`foundations/` only holds
`.gitkeep`). The agent creates each file during Setup the first time the user provides
information for its scope, and keeps adding to the right file, by scope, as the conversation
goes. A file that doesn't exist yet means its scope has no information yet — that's a Setup gap.
The four A1-A4 files are the input the `engine/` scripts read for the first iteration of
frameworks and pieces.

| File | Created when | Updated when |
|---|---|---|
| `BRAND.md` | At the start of Setup, as soon as the brand name / first info is known — together with the first A1-A4 file | Every time any A1-A4 file is created or changes (status, summary, open gaps) |
| `COLORS.md` / `FONTS.md` / `LOGOS.md` / `COPYS.md` | The first time the user gives information for that file's scope | Whenever new information for that scope arrives or a value is corrected |

### Foundations file format (single definition — every other document references this)

Every foundations file except `BRAND.md` has the same two parts, in this order (`BRAND.md` is
the index, not a source — it has no token block and is never parsed by the engine; its own shape
is defined in "The foundations index" below):

1. **Token block** — the first fenced ` ```yaml ` block in the file, under a `## Tokens` heading.
   This is what the `engine/` scripts parse; they read only this block, never the prose.
   - A flat map: one `token.name: value` pair per line. Keys are the full dotted token name per
     `schema.md` — no nesting, no anchors, no multi-line values.
   - Values are quoted strings (`"#E4002B"`, `"700"`, `"999px"`).
   - A file reference is a quoted path relative to the project root, pointing into `resources/`
     (e.g. `"resources/fonts/BrandSans-Bold.otf"`). The file itself is never copied into
     `foundations/`.
   - A token the brand is known to have but whose value hasn't been provided is written as
     `null` with a `# gap:` comment. The engine refuses to render with a `null` it needs — it
     never substitutes a default. A token nobody has mentioned is simply absent.
   - A file whose scope has no machine-readable values (typically `COPYS.md`) still has the
     block, empty (`{}`), so every file parses the same way.
2. **Usage rules** — prose after the block, under `## Usage rules`: when and how each token is
   used, do/don't examples, notes. Prose never restates a value that is in the block — it refers
   to it by token name.

Minimal example (`foundations/COLORS.md`):

````markdown
# Colors

## Tokens

```yaml
color.palette.red: "#E4002B"
color.palette.white: "#FFFFFF"
color.palette.navy: null  # gap: brand mentions a navy, hex not provided yet
radius.pill: "999px"
```

## Usage rules

- `color.palette.red` is the brand's signature color; it is never used for body text.
````

### The foundations index → `foundations/BRAND.md` (single definition)

The entry point to the brand's foundations: the agent reads `BRAND.md` first, then loads only the
A1-A4 files the task at hand needs. It summarizes and points — it never restates a value (no hex,
no font file path, no tone or usage rule text); at most it names tokens. Every fact stays in the
file that owns its scope, so a change to a fact is made there and only the index's status/summary
line is refreshed here.

Exempt from the token-block format: no `## Tokens` block, not parsed by the `engine/` (the engine
reads the A1-A4 token blocks directly). It always has these sections, in this order:

1. **Title + description** — `# <Brand name>`, then one or two sentences on what the brand is.
2. **`## Foundations files`** — one row per A1-A4 file, always all four: file, scope, status, and
   a one-line summary of what it currently covers. Status is one of: `created`, `created — open
   gaps` (its token block has `null # gap:` tokens), `not created yet` (Setup gap).
3. **`## Open gaps`** — a short list: each missing file and each open `null # gap:` token, by
   token name, pointing to the file that holds it. `None` when there are none.
4. **`## Resources`** — the `resources/` subfolders that hold this brand's files, with a few
   words on what each has. Only folders that actually hold files.

Minimal example (`foundations/BRAND.md`):

````markdown
# Acme

Acme is a regional supermarket chain; its ads are bold, price-led and family-oriented.

## Foundations files

| File | Scope | Status | Covers |
|---|---|---|---|
| `COLORS.md` | A1 palette, brand-wide radii/patterns | created — open gaps | 3 palette colors (`color.palette.red`, `.white`, `.navy`), `radius.pill` |
| `FONTS.md` | A2 typography | created | 1 family (`font.family.display`), 2 weights, file refs |
| `LOGOS.md` | A3 logo | not created yet | — |
| `COPYS.md` | A4 tone, legal | created | tone, do/don't lines, prohibited claims |

## Open gaps

- `LOGOS.md` — no logo information yet.
- `COLORS.md` — `color.palette.navy` value not provided.

## Resources

- `resources/fonts/` — display typeface files.
````

### A1. Base brand palette and brand-wide tokens → `foundations/COLORS.md`

The brand's complete official color set as `color.palette.*` tokens — named, not yet assigned to
a framework role (that's B1). These names are never referenced directly from a framework: a
framework always goes through a role (B1). Each color may carry a usage note in the prose part.

Other tokens that are truly brand-wide and not typographic also live here: `radius.*` values the
brand applies everywhere, and foundation-level `pattern.*` slot names (see `schema.md`). A radius
or pattern specific to one framework stays in that framework's document.

### A2. Base typography → `foundations/FONTS.md`

- **Inventory**: the complete set of families/weights the brand has available — could be 2, could
  be 7 — as `font.family.*` / `font.weight.*` tokens.
- **Files**: each family/weight's typeface file in `resources/fonts/`, referenced as a
  `font.file.*` token (by path, never duplicated).
- **Brand-wide usage rules** (prose): rules that hold in every framework — e.g. "family X is only
  for headlines", "body copy is never set in the display face".

Which family a given element (headline, sub, CTA) uses INSIDE a specific framework — same as its
sizes and scaling rules — does NOT go here: that's B5, because that assignment changes framework
to framework. `FONTS.md` holds the brand-wide rules B5 must respect.

### A3. Logo → `foundations/LOGOS.md`

- **Files**: each logo version in `resources/logos/`, referenced by path as a `logo.*` token
  (e.g. `logo.primary.onLight`, `logo.secondary.onDark`) — never duplicated.
- **Usage rules**, only the ones the user defines during Setup — none is mandatory: which version
  is primary vs. secondary, which goes on light vs. dark backgrounds, minimum clear-space, when to
  use each version. A rule the user hasn't defined is either absent or marked "not defined yet" —
  never invented. Clear-space, if defined, is a brand rule, not a framework one — it always
  applies, even though its exact position and measurement is defined per framework in B6.

### A4. Copy tone and legal boundaries → `foundations/COPYS.md`

- How the brand communicates: tone (e.g. 2-3 adjectives), voice, and "do" / "don't" example
  lines.
- Explicit list of prohibited claims (health, legal, competitor comparisons, etc.) and why they're
  prohibited.

---

## Part B — Framework parameters (one at a time, see `framework-construction.md`)

These categories exist inside the configuration of EACH framework, because their value differs
depending on what that framework solves. They are not filled in ahead of time. They all end up
living in one place: that framework's `frameworks/<name>.md` document — there is no code, the
document IS the complete specification.

### B0. Intent, objective, and channels

Resolved first, before any other category — without this there's no way to later validate
whether the framework delivers what was expected of it:

| Field | Question |
|---|---|
| Intent | Why does this framework exist in the communication strategy? What role does it play? |
| Objective | What must a piece from this framework concretely achieve? |
| Channels | Which channels does it run on? (this determines which B7 buckets apply) |

### B1. Color roles for this framework (`color.role.*`)

Which base-palette (A1) color plays each role in this specific framework. The "token name" column
is what the rest of the document uses to refer to this role — the raw hex is never written again
once it's defined here:

| Role | Token name | Color (from A1) |
|---|---|---|
| Primary background | `color.role.background.primary` | |
| Secondary background / accent | `color.role.background.secondary` | |
| Text on light background | `color.role.text.onLight` | |
| Text on dark background | `color.role.text.onDark` | |

### B2. Image mode

- **Product mode**: automatic cutout + contain (never deformed) + no added shadow.
- **Photo mode**: cover + per-piece framing + respects the logo's exclusion zone.

Each framework declares ONE of the two modes. Before using any asset, confirm the file is
actually clean (no baked-in shadow or background from whoever delivered it) and that its colors
read well against EVERY background color it will be used with — if not, a new cutout is
requested.

### B3. Framework elements

The complete list of EVERYTHING that makes up the framework — not just text. For each element:
whether it's dynamic (changes by copy, variant, or size) or fixed (always the same), and its
type:

| Element | Type (text / image / shape / empty space) | Dynamic or fixed? | Depends on |
|---|---|---|---|
| Headline | text | Dynamic | copy |
| Logo | image | Fixed | — |
| Product/photo | image | Dynamic | variant (B4) |
| Background strip | shape | Fixed | — |
| Platform CTA zone | empty space | Fixed | — |
| Price / discount | text | Dynamic | content variant (B4), offer-type only |

No element of the framework is left off this list — if something appears in any of the
framework's sources and isn't here, it isn't defined yet. This is resolved BEFORE B4 (variants),
because variants are described in terms of which elements from this list change.

**This list is also the contract for any bulk copy-delivery mechanism** — spreadsheet, feed, CSV,
or whatever the team uses to produce many pieces at once. Its columns/fields map 1:1 to the
dynamic elements listed here — a loose field that isn't on this list is never invented. If the
framework has content variants (B4), add a column indicating which variant applies to each row —
the rest of the columns don't change between variants, because the composition is the same.

### B4. Variants

A variant is a **variation of components over the SAME composition** — what's shown, what it
says, or which color/product it uses. It's never a different layout of elements: if something
needs a different composition, that's a new framework, not a variant of this one.

There are two types, and a framework can have one, the other, or both at once:

**Content variants** — which B3 elements appear and what they say, over the same structure:

| Variant | Shows (from B3) that others don't | Hides |
|---|---|---|
| e.g. "Offer" | price, discount, legal disclaimer | — |
| e.g. "Invitation" | invitation message/CTA | price, discount |

**Product/color variants** — which role (from B1) or which asset (from B8) each one uses:

| Variant | Roles that change (from B1) | Asset (product/photo, from B8) |
|---|---|---|
| Variant A | | |
| Variant B | | |

A product/color variant can be locked to a single set, or have a bounded set of allowed options
(e.g. "product X can go with set A or set B, depending on the piece") — in that case the
left-hand column lists the full set; which one applies to a specific piece is decided when that
piece is produced.

### B5. Typography and text-scaling rules

Only for the text elements identified in B3, by content variant if applicable:

| Element | Family (from A2) | Min–max size | Scaling rule | Character cap (narrowest size) |
|---|---|---|---|---|
| Headline | | | | |
| Sub | | | | |
| CTA | | | | |
| Price | | | | |

Practical rule: it's better to shorten the copy than to rely on auto-scaling to save an
oversized line — the cap should be conservative, not the theoretical maximum.

**Sizes in this table are expressed as a proportion of the canvas (%), never in absolute
pixels** — a framework covers several sizes (B7), and a pixel value here would be fictional
outside one specific size. The conversion to exact pixels per size goes in B6.

### B6. Exact measurements

For each B3 element, and for each B7 size if the value differs between sizes: position, distance
to neighboring elements, margins, corner radii, elevation/shadow, and stroke width and color.
None of this is left "eyeballed" — if a value isn't defined yet, it's asked before assuming it.

| Element | Size (from B7) | Position / distance | Margin | Radius (`radius.*`) | Elevation / shadow | Stroke |
|---|---|---|---|---|---|---|
| | | | | | | |

Expected level of detail example: "Logo: horizontally centered, `spacing.safe.top` = 6% of
canvas height; no shadow; no stroke." — not "the logo goes up top, roughly centered."

### B7. Sizes and buckets this framework covers

| Bucket | Sizes it includes | Reuses pieces from another bucket? |
|---|---|---|

### B8. Assets specific to this framework

Photos, product cutouts — shared across all sizes of this framework, but not necessarily with
other frameworks.
