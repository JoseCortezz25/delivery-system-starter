# Structure and Assets

This is the only place that defines the folder structure. No other document repeats it — they
only reference it. See the non-redundancy rule below.

## What exists in a project

```
project/
├── foundations/                  # Foundations primitive — tokenized once, shared by every framework
│   ├── BRAND.md                  # index, read first: brand summary + status of the four files below (no values)
│   ├── COLORS.md                 # palette + brand-wide radius/pattern tokens (A1)
│   ├── FONTS.md                  # typography inventory, font file refs, brand-wide type rules (A2)
│   ├── LOGOS.md                  # logo file refs + user-defined logo usage rules (A3)
│   └── COPYS.md                  # tone, voice, do/don't, prohibited claims, legal (A4)
├── frameworks/
│   └── <name>.md                 # one document per framework — full spec: B0-B8, every size it covers
├── resources/                    # Resources primitive (insumos) — every raw brand asset, by type
│   ├── logos/
│   ├── images/
│   ├── videos/
│   ├── icons/
│   ├── sounds/
│   └── fonts/
├── content/                      # Content generation primitive — execution output
│   ├── <N>-<project-name>/
│   │   └── <size>/               # final pieces of that delivery, by size
│   └── <N+1>-<project-name>/
├── references/                   # approved-output index — thumbnails/montages for quick lookup
│   └── <framework>/               # one or more reference images per framework — one per size
│       └── <size>[-<variant>].jpg  # and/or content type is common, not a single combined file
├── knowledge/                    # Knowledge primitive — brand-specific facts, not a resource store
└── engine/                       # rendering engine — scripts that build the pieces
```

Everything here belongs to ONE brand. A project never contains `foundations/` for two different
brands — if a new brand shows up, it's a new project, with this same tree, empty.

**`content/<N>-<project-name>/` is sequential and never reused.** A new project or campaign
always gets the next number — past deliveries are never overwritten or renumbered.

## Where each asset goes

- **Every raw brand asset lives in `resources/`, organized by type — with no exception.** A logo
  used everywhere and a photo used by only one framework both live here.
- **A framework-specific asset is not moved into `frameworks/`.** It stays in `resources/`, under
  its type folder; a subfolder per framework is only created if the number of files actually
  justifies it — the same criterion used for variants (see `framework-construction.md`): don't
  split until the volume asks for it.
- **A file is never duplicated across folders.** If two frameworks need the same asset, it lives
  once in `resources/`, and each `frameworks/<name>.md` references it by name.

## Non-redundancy rule between documents

Each fact lives in exactly one place. Everything else references it, never copies it.

| Fact | Lives in | How it's referenced |
|---|---|---|
| Base palette and brand-wide `radius.*` / `pattern.*` tokens | `foundations/COLORS.md` | By token name (`color.palette.*`, via a `color.role.*`) — a hex is never repeated inside a `frameworks/<name>.md` |
| Typography inventory, font files, brand-wide type rules | `foundations/FONTS.md` | By token name (`font.family.*`, `font.weight.*`) — per-element assignment stays in the framework's B5 |
| Logo files and logo usage rules | `foundations/LOGOS.md` | By token name (`logo.*`) — the file itself lives once in `resources/logos/` |
| Tone, voice, prohibited claims, legal (brand-wide) | `foundations/COPYS.md` | "see `foundations/COPYS.md`" — a tone or legal rule is never repeated inside a `frameworks/<name>.md` |
| Brand name + short description, and the index/status of the four foundations files (status, one-line summary, open gaps, `resources/` pointers) | `foundations/BRAND.md` | Read first, then the file it points to — it never holds a value or rule itself; the facts live only in the four files above |
| Intent, objective, channels, color roles, image mode, elements, variants, text scaling (shared by every size of ONE framework) | The matching section of that `frameworks/<name>.md` | Every size row references them by name — never redeclared or repeated |
| Exact measurements of ONE specific size | That size's row, inside the same `frameworks/<name>.md` | Another size never copies these values — if it shares a ratio with another, that's noted and referenced, not repeated |
| This folder structure | This document (`structure-and-assets.md`) | `methodology.md` only mentions it and links here |

Before creating a new document or file to note a clarification or adjustment, the required
question is: **does this already have a place to live?** Almost always the answer is yes — either
it's a correction to the matching `foundations/` file, or an adjustment to a section of
`frameworks/<name>.md` (a general rule if it affects every size, or that size's row if it's just
its measurement). The
change stays inside the existing document, not in a separate file. A new standalone document is
the exception, not the norm.

## Setup completeness checklist

The single source for deciding whether a brand's knowledge is complete (Setup is closed) or has
gaps (Setup is open) — used by the `codex-workflow` skill at the start of every session, not only
for a brand-new project. Any unchecked item relevant to the requested piece is an open gap.

- [ ] `foundations/BRAND.md` exists and is up to date with the four files below (status, summary,
      open gaps match what's actually in them) — shape: `tokenization.md` Part A
- [ ] `foundations/COLORS.md` exists, is approved, and its token block has no `null` gaps the
      requested piece needs (format and scope: `tokenization.md` Part A)
- [ ] `foundations/FONTS.md` exists, is approved, and every family it declares has a `font.file.*`
      pointing to a file present in `resources/fonts/`
- [ ] `foundations/LOGOS.md` exists, is approved, and every `logo.*` points to a file present in
      `resources/logos/` — its usage rules are whatever the user has defined; an undefined rule is
      not a gap unless the requested piece depends on it
- [ ] `foundations/COPYS.md` exists and is approved (tone + prohibited claims), before any copy is
      drafted
- [ ] `resources/logos/` has every logo version the approved frameworks need, each referenced from
      `foundations/LOGOS.md`
- [ ] `resources/` has the images, icons, videos, and sounds the brand provides and the approved
      frameworks require — referenced by name, none missing on disk
- [ ] For every approved framework: `frameworks/<name>.md` exists, with every category resolved
      and no gaps for at least its first size
- [ ] Brand-specific facts the user has taught (decisions, corrections) are recorded in
      `knowledge/`

Checked per delivery during Execution — not a Setup gap:

- [ ] `content/` has a numbered folder for this project/campaign — never a reused one
- [ ] `references/<framework>/` has at least one reference image per approved framework — a
      single combined montage is not required, one image per size/variant is the common case
