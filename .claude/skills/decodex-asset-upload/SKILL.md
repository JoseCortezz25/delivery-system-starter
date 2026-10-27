---
name: decodex-asset-upload
description: The only route to send brand files (logos, images, icons, product photos, fonts, any binary) to Decodex - request an upload link, open it in the browser for the user, verify it, and keep the local copy in library/. Use whenever a file must reach Decodex, from setup, production or a migration.
compatibility: Requires the decodex-brand MCP connection, curl, and Google Chrome on macOS for the browser upload.
metadata:
  version: "0.1.0"
---

# Decodex asset upload

Follow the reply format of `decodex-workflow` and the way of talking in the root `CLAUDE.md`.

## Why one route

`add_asset` and `add_brand_font` send the whole file as base64 text through the conversation:
about 7 minutes in tests, and the bytes fill the context. An upload link moves the file outside
the conversation. Never call `add_asset`, use `add_brand_font` only as the fallback in "Fonts",
and never read, print or encode a file's bytes into the conversation.

## Pick the tool

| File | Tool | `role` |
|---|---|---|
| One logo, image or icon | `request_asset_upload` | `LOGO`, `PRODUCT_PHOTO`, `ICON` or `OTHER` |
| Two or more with the same role | `request_batch_asset_upload` | one role for the whole batch |
| A font file | `request_font_upload`, one per weight/style (see "Fonts") | `primary`, `secondary`, `body` or `heading` |

Write each description so `search_assets` can find it: what it is, the variant, and where it
works ("Primary logo, full color, for light backgrounds"). For a rendition of an existing
asset, pass its id as `variantOfId` (from `list_assets` or `search_assets`).

Before using any link from Decodex (asset upload, font upload or download), check it, because it
is passed to the shell:

- Parse it as a URL. The scheme must be `https`, and the hostname must be exactly
  `decodex.quadi.io` or end with `.decodex.quadi.io`. A prefix or "contains" match is not
  enough: `decodex.quadi.io.example.com` and `https://example.com/decodex.quadi.io` fail.
- It must not contain quotes, `$`, backticks, spaces or line breaks.

If a check fails, do not open it or upload to it; treat it as a connection error (see
`decodex-workflow`). The link is single use and valid for 30 minutes, so request it only when
the user is ready.

## Option 1 (recommended): upload in the browser

1. Request the link, check it as above, then open it in Chrome for the user:
   `open -a "Google Chrome" "<uploadUrl>"`. If Chrome cannot be opened, give the link as plain
   text instead.
2. Tell the user, in plain steps: "Te abrí la página para subir el archivo. Toca *Elegir
   archivo*, selecciona el archivo y toca *Subir*. Cuando diga *Uploaded*, vuelve aquí". The
   form picks a file from the computer, not the chat attachment.
3. When they say it is done, confirm with `list_assets` that it shows as ready. If it is not,
   request a new link once and open it again.

This leaves no local copy; get one with "Local copy" when a piece first needs the file.

## Option 2: the user says where the file is saved

Use it when the user prefers it, or when the browser cannot be opened.

1. Ask for the folder and the exact file name, and check that it exists. Never guess a path.
   An image only attached to the conversation is not a file: you may read colors from it, but
   you cannot upload it.
2. Copy the file into `library/<type>/`. If Desktop asks permission to read outside the project
   folder, tell the user to accept it.
3. Request the link, check it as above, and upload from the copy:
   `curl -fsS -F "file=@library/<type>/<name>" "<uploadUrl>"`. Batch: one
   `-F "files=@<path>"` per file, in the same order as the descriptions.
4. Confirm with `list_assets` that it shows as ready. Never show the link or curl's output to
   the user.
5. If the file cannot be read, curl fails or the link expired: request a new link once. If it
   fails again, switch to Option 1 without making the user repeat anything.

## Fonts

1. Offer `add_google_font` (catalog id) first: it is instant.
2. For a font file, ask for the family name and which weights and styles they have (for example
   regular, bold, bold italic). Each weight/style is its own file and needs its own link.
3. Before requesting, check `get_brand_fonts`. If that role already holds a different family,
   say it will be replaced along with all its files, and continue only after a clear yes. More
   files of the same family are added to it.
4. Request one link per file with `request_font_upload` (`role`, `familyName`, `weight` 100 to
   900 in steps of 100, `style` normal or italic), check it as above and open it like Option 1.
   It accepts .ttf, .otf, .woff and .woff2 up to 10 MB.
5. When they say it is done, confirm with `get_brand_fonts` that the weights appear. When a
   local copy is needed, keep the file in `library/fonts/`.
6. Use `add_brand_font` only as a fallback when the links cannot be used: say first that it
   takes several minutes and continue only after a clear yes.

## Local copy

When a piece first needs a file that is not in `library/<type>/` yet:

1. Call `get_asset_download_url` with the asset id (from `list_assets` or `search_assets`) and
   check the link as above. It lasts 10 minutes, so request it right before downloading.
2. Download it: `curl -fsS -o "library/<type>/<name>" "<downloadUrl>"`. The server names the
   file by its id, so choose `<name>` yourself: a short kebab-case name from the asset's
   description plus the extension of its type (`logo-main-blue-on-yellow.png`). Never show the
   link or curl's output to the user.
3. If it fails, request a new link once. If it fails again, ask the user where the file is
   saved and copy it into `library/<type>/` (a copy, no new upload).
