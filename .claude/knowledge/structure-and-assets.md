# Structure and Assets

This is the only place that defines the folder structure. No other document repeats it — they
only reference it. See the non-redundancy rule below.

Brand data itself lives in Decodex (see the root `CLAUDE.md`), the source of truth. The folders
below are the local layer: framework drafts, local copies of assets, generated output and the
engine. `foundations/` and `frameworks/` are a local baseline: an older project's local
brand data, synced once to Decodex with `decodex-sync` and then locked (see "Sync marker" below).

## What exists in a project

```
project/
├── foundations/                  # local baseline — synced once to Decodex, then locked
├── frameworks/                   # local baseline — synced once to Decodex, then locked
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
├── codex-lock.json               # project lock — written once by the plugin, protected (see below)
└── .decodex-sync.json            # sync marker — written once by decodex-sync, protected (see below)
```

Everything here belongs to ONE brand. A project never contains foundations for two different
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

## Sync marker (`.decodex-sync.json`)

Written once by `decodex-sync` (its `lock-local-folders.sh` script) after every item of
`foundations/` and `frameworks/` was saved to Decodex and read back. It is absent in the template.

```json
{
  "schemaVersion": 1,
  "syncedAt": "<ISO 8601 UTC>",
  "brandId": "<Decodex brand id>",
  "brandName": "<brand name>",
  "folders": ["foundations", "frameworks"],
  "files": [{ "path": "foundations/<file>", "sha256": "<hex>" }]
}
```

While it exists the hooks freeze both folders for the AI (no read, search or change, and no
search over the project root); see `RULES.md`. It is add-only: the AI never edits or deletes it.
Only the user unlocks the project, by deleting it themselves.

## Where each asset goes

- **Every raw brand asset is uploaded to Decodex first (see `decodex-asset-upload`), and then a
  copy lives in `library/`, organized by type.** A file the user uploaded in the chat panel or
  in the browser gets
  its local copy, downloaded from Decodex, when a piece first needs it. This applies to every
  asset, whether every framework uses it (the main logo) or only one does (a product photo):
  its copy goes in `library/<type>/` all the same.
- **A framework-specific asset is not moved into `frameworks/` or a framework-specific folder.** It stays in
  `library/`, under its type folder; a subfolder per framework is only created if the number of files actually
  justifies it — the same criterion used for variants (see `framework-construction.md`): don't
  split until the volume asks for it.
- **A file is never duplicated across folders.** If two frameworks need the same asset, it lives
  once in `library/`, and each framework document references it by name.

## Non-redundancy rule between documents

Each fact lives in exactly one place. Everything else references it, never copies it.

| Fact | Lives in | How it's referenced |
|---|---|---|
| Base palette, base typography, logo, tone, legal (brand-wide) | Decodex (`get_brand_colors`, `get_brand_fonts`, `get_brand_voice`, `get_foundations`) | "see the brand" — a hex or a tone rule is never repeated inside a framework document |
| Intent, objective, channels, color roles, image mode, elements, variants, text scaling (shared by every size of ONE framework) | The matching section of that framework (`get_framework` / its working draft) | Every size row references them by name — never redeclared or repeated |
| Exact measurements of ONE specific size | That size's row, inside the same framework document | Another size never copies these values — if it shares a ratio with another, that's noted and referenced, not repeated |
| This folder structure | This document (`structure-and-assets.md`) | `methodology.md` only mentions it and links here |

Before creating a new document or file to note a clarification or adjustment, the required
question is: **does this already have a place to live?** Almost always the answer is yes — either
it's a correction to the brand in Decodex, or an adjustment to a section of the framework document (a
general rule if it affects every size, or that size's row if it's just its measurement). The
change stays inside the existing document, not in a separate file. A new standalone document is
the exception, not the norm. A brand fact goes to `add_knowledge`, never to a new file.

## Where each kind of data lives

| What | Decodex tool (write / read) | Stays local |
|---|---|---|
| Palette | `set_brand_color` / `get_brand_colors` | — |
| Fonts | upload panel (`open_upload_inbox` → `apply_inbox_classification`), `request_font_upload`, `add_google_font` (`add_brand_font` fallback) / `get_brand_fonts` (with a download link per uploaded file) | — |
| Tone, legal | `set_brand_voice`, `set_brand_core` / `get_brand_voice` | — |
| Other foundations: named tokens, logo clear-space | `set_foundation`, `delete_foundation` / `get_foundations` | — |
| Asset files | upload panel (`open_upload_inbox` → `apply_inbox_classification`), `request_asset_upload`, `request_batch_asset_upload` / `get_asset`, `list_assets`, `search_assets`, `get_asset_download_url` | — |
| Framework spec | `add_framework` / `list_frameworks`, `get_framework` | its working draft (temporary) while it's built |
| Brand facts, colorways | `add_knowledge`, `list_knowledge`, `delete_knowledge` | — |
| Designer learnings | `save_piece_learning` / `search_piece_learnings` | — |

Every kind of brand data now has a Decodex tool. Local content still in `foundations/` or
`frameworks/` is passed to Decodex once with `decodex-sync`, which then locks both folders.

## New-project startup checklist

- [ ] `get_brand` confirms the right brand
- [ ] `get_brand_setup_status` shows no gaps (see `tokenization.md` Part A)
- [ ] Logos in every version needed are uploaded to Decodex (`list_assets`)
- [ ] For every approved framework: saved in Decodex (`get_framework`), with every category resolved
      and no gaps for at least its first size
- [ ] `content/` has a numbered folder for this project/campaign — never a reused one
- [ ] `references/<framework>/` has at least one reference image per approved framework — a
      single combined montage is not required, one image per size/variant is the common case
