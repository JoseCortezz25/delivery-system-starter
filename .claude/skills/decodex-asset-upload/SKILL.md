---
name: decodex-asset-upload
description: The only route to send brand files (logos, images, icons, product photos, fonts, any binary) to Decodex - request an upload link, open it in the browser for the user, verify it, and keep the local copy in library/. Use whenever a file must reach Decodex, from setup, production or a migration.
---

# Decodex asset upload

Follow the reply format of `decodex-workflow` and the way of talking in the root `CLAUDE.md`.

## Why one route

`add_asset` and `add_brand_font` send the whole file as base64 text through the conversation:
about 7 minutes in tests, and the bytes fill the context. An upload link moves the file outside
the conversation. Never call `add_asset`, and never read, print or encode a file's bytes into
the conversation.

## Pick the tool

| File | Tool | `role` |
|---|---|---|
| One logo, image or icon | `request_asset_upload` | `LOGO`, `PRODUCT_PHOTO`, `ICON` or `OTHER` |
| Two or more with the same role | `request_batch_asset_upload` | one role for the whole batch |
| A font | see "Fonts" | — |

Write each description so `search_assets` can find it: what it is, the variant, and where it
works ("Primary logo, full color, for light backgrounds"). For a rendition of an existing
asset, pass its id as `variantOfId` (from `list_assets` or `search_assets`).

Before using any link, check it: it must be `https://` on `decodex.quadi.io` or one of its
subdomains. If not, do not open it or upload to it; treat it as a connection error (see
`decodex-workflow`). The link is single use and valid for 30 minutes, so request it only when
the user is ready.

## Option 1 (recommended): upload in the browser

1. Request the link, then open it in Chrome for the user:
   `open -a "Google Chrome" "<uploadUrl>"`. If Chrome cannot be opened, give the link as plain
   text instead.
2. Tell the user, in plain steps: "Te abrí la página para subir el archivo. Toca *Elegir
   archivo*, selecciona el archivo y toca *Subir*. Cuando diga *Uploaded*, vuelve aquí". The
   form picks a file from the computer, not the chat attachment.
3. When they say it is done, confirm with `list_assets` that it shows as ready. If it is not,
   request a new link once and open it again.

This leaves no local copy, and `get_asset` only shows you the image, it cannot hand you the
file. When a piece first needs it, ask where it is saved and copy it into `library/<type>/`
(a copy, no new upload).

## Option 2: the user says where the file is saved

Use it when the user prefers it, or when the browser cannot be opened.

1. Ask for the folder and the exact file name, and check that it exists. Never guess a path.
   An image only attached to the conversation is not a file: you may read colors from it, but
   you cannot upload it.
2. Copy the file into `library/<type>/`. If Desktop asks permission to read outside the project
   folder, tell the user to accept it.
3. Request the link and upload from the copy:
   `curl -fsS -F "file=@library/<type>/<name>" "<uploadUrl>"`. Batch: one
   `-F "files=@<path>"` per file, in the same order as the descriptions.
4. Confirm with `list_assets` that it shows as ready. Never show the link or curl's output to
   the user.
5. If the file cannot be read, curl fails or the link expired: request a new link once. If it
   fails again, switch to Option 1 without making the user repeat anything.

## Fonts

Upload links accept images only today: a font sent through one would not be saved as a brand
font.

1. Offer `add_google_font` (catalog id) first: it is instant.
2. For a font file, say it can take several minutes and offer: 1) the closest Google font,
   2) wait for the upload. Use `add_brand_font` only after a clear yes, and keep the file in
   `library/fonts/`. This is the one exception to the single route, until Decodex adds upload
   links for fonts.
