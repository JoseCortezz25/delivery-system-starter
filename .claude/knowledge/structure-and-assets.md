# Structure and Assets

This is the only place that defines the folder structure. No other document repeats it — they
only reference it. See the non-redundancy rule below.

Brand data itself lives in Decodex (see the root `CLAUDE.md`). The folders below are the local
layer: a copy of what Decodex holds, plus whatever its tools don't cover yet.

## What exists in a project

```
project/
├── foundations/                  # Foundations primitive — tokenized once, shared by every framework
├── frameworks/
│   └── <name>.md                 # one document per framework — full spec: B0-B8, every size it covers
├── library/                      # Insumos primitive — every raw brand asset, organized by type (uploaded to Decodex first)
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
├── engine/                       # rendering engine — scripts that build the pieces
└── codex-lock.json               # project lock — written once by the plugin, protected (see below)
```

Everything here belongs to ONE brand. A project never contains `foundations/` for two different
brands — if a new brand shows up, it's a new project, with this same tree, empty.

**`content/<N>-<project-name>/` is sequential and never reused.** A new project or campaign
always gets the next number — past deliveries are never overwritten or renumbered.

## Project lock (`codex-lock.json`)

The plugin writes it once, when it creates the project, and from then on it is protected: the AI
never edits or deletes it. The template itself has none.

```json
{
  "schemaVersion": 1,
  "harness": { "name": "decodex", "version": "<template tag>", "repo": "<template git URL>", "commit": "<commit sha>" },
  "brand": { "name": "<brand name as it appears in Decodex>", "codexVersion": "<brand format version>" },
  "project": { "name": "<project slug>", "purpose": "<free text>", "createdAt": "<ISO 8601 UTC>" },
  "createdWith": { "plugin": "<plugin name>", "pluginVersion": "<plugin version>" }
}
```

The router in `decodex-workflow` reads `brand.name`, and `brand.id` when present. `brand.id` is
optional: the plugin does not write it yet, because the project is created before connecting to
Decodex. The other fields are informational.

## Where each asset goes

- **Every raw brand asset is uploaded to Decodex first (see `decodex-asset-upload`), and then a
  copy lives in `library/`, organized by type.** A file the user uploaded in the browser gets
  its local copy, downloaded from Decodex, when a piece first needs it. This applies to every
  asset, whether every framework uses it (the main logo) or only one does (a product photo):
  its copy goes in `library/<type>/` all the same.
- **A framework-specific asset is not moved into `frameworks/`.** It stays in `library/`, under
  its type folder; a subfolder per framework is only created if the number of files actually
  justifies it — the same criterion used for variants (see `framework-construction.md`): don't
  split until the volume asks for it.
- **A file is never duplicated across folders.** If two frameworks need the same asset, it lives
  once in `library/`, and each `frameworks/<name>.md` references it by name.

## Non-redundancy rule between documents

Each fact lives in exactly one place. Everything else references it, never copies it.

| Fact | Lives in | How it's referenced |
|---|---|---|
| Base palette, base typography, logo, tone, legal (brand-wide) | Decodex (`get_brand_colors`, `get_brand_fonts`, `get_brand_voice`, `get_foundations`); `foundations/` only for what the tools don't cover | "see the brand" — a hex or a tone rule is never repeated inside a `frameworks/<name>.md` |
| Intent, objective, channels, color roles, image mode, elements, variants, text scaling (shared by every size of ONE framework) | The matching section of that framework (`get_framework` / `frameworks/<name>.md`) | Every size row references them by name — never redeclared or repeated |
| Exact measurements of ONE specific size | That size's row, inside the same `frameworks/<name>.md` | Another size never copies these values — if it shares a ratio with another, that's noted and referenced, not repeated |
| This folder structure | This document (`structure-and-assets.md`) | `methodology.md` only mentions it and links here |

Before creating a new document or file to note a clarification or adjustment, the required
question is: **does this already have a place to live?** Almost always the answer is yes — either
it's a correction to the brand in Decodex (or `foundations/`), or an adjustment to a section of `frameworks/<name>.md` (a
general rule if it affects every size, or that size's row if it's just its measurement). The
change stays inside the existing document, not in a separate file. A new standalone document is
the exception, not the norm. A brand fact goes to `add_knowledge`, never to a new file.

## Where each kind of data lives

| What | Decodex tool (write / read) | Stays local |
|---|---|---|
| Palette | `set_brand_color` / `get_brand_colors` | token names |
| Fonts | `request_font_upload`, `add_google_font` (`add_brand_font` fallback) / `get_brand_fonts` | — |
| Tone, legal | `set_brand_voice`, `set_brand_core` / `get_brand_voice` | — |
| Other foundations | `set_foundation` / `get_foundations` | — |
| Asset files | `request_asset_upload`, `request_batch_asset_upload` / `get_asset`, `list_assets`, `search_assets`, `get_asset_download_url` | logo clear-space rules |
| Framework spec | `add_framework` / `list_frameworks`, `get_framework` | — |
| Brand facts | `add_knowledge`, `list_knowledge`, `delete_knowledge` | — |
| Designer learnings | `save_piece_learning` / `search_piece_learnings` | — |
| Colorways | no tool yet | all of it |

What stays local lives in `foundations/` until the tools cover it.

## New-project startup checklist

- [ ] `get_brand` confirms the right brand
- [ ] `get_brand_setup_status` shows no gaps (see `tokenization.md` Part A)
- [ ] Logos in every version needed are uploaded to Decodex (`list_assets`)
- [ ] For every approved framework: saved in Decodex (`get_framework`), with every category resolved
      and no gaps for at least its first size
- [ ] `content/` has a numbered folder for this project/campaign — never a reused one
- [ ] `references/<framework>/` has at least one reference image per approved framework — a
      single combined montage is not required, one image per size/variant is the common case
