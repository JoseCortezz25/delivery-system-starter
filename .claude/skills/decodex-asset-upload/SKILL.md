---
name: decodex-asset-upload
description: The only route to send brand files (logos, images, icons, product photos, fonts, any binary) and brand documents (.md, .txt, PDF, .pptx, .docx) to Decodex - the upload panel in the chat when available, otherwise an upload link opened in the browser, then verify it. Also defines the verified local copy (a cache of Decodex downloads in library/ or resources/). Use whenever a file must reach Decodex, from setup, production or a migration, and before a piece uses a brand file.
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

## Option 0 (recommended when available): the upload panel in the chat

Use it whenever `open_upload_inbox` is in your tool list (it needs the configure permission and
Decodex must have it turned on). It takes every kind of file at once, fonts and `.md`/`.txt` documents included, so the
user drops everything in one go instead of one link per file. If the tool is not there, go to
Option 1.

1. Call `open_upload_inbox`. In Claude Desktop or the web a panel opens inside the chat, with
   the brand's name at the top. Tell the user, in plain steps: "Te abrí un panel aquí en el
   chat. Revisa que arriba diga el nombre de tu marca, arrastra todos los archivos (logos,
   fotos, fuentes, documentos .md o .txt) y toca *Listo* cuando termines". If no panel appears, the tool's text
   carries a backup link to the same upload page: check it as above and open it in Chrome like
   Option 1. A session lasts 30 minutes and takes up to 50 files: images up to 25 MB, fonts
   (.ttf, .otf, .woff, .woff2) up to 10 MB. PDF, .pptx and .docx are rejected by the panel (see
   "Documents").
2. The files land unclassified. For fonts the panel shows "family · weight · style" and lets
   the designer correct them there; that saves through `update_inbox_item`, which only the
   panel calls. Never call it yourself.
3. When the user is done, call `list_inbox_items`. A designer's correction on a font is the
   truth: use it over the detected values.
4. Classify every file automatically — do not ask the user about each one. For a font, use the
   family, weight and style the panel detected or the designer corrected. For an image, infer
   its `role` from the file name (a logo to `LOGO`, a product photo to `PRODUCT_PHOTO`, an icon
   to `ICON`, otherwise `OTHER`) and write its description from the name as in "Pick the tool";
   pass `variantOfId` only when the name clearly marks a rendition of an existing asset. Then
   call `preview_inbox_classification`. If it warns that an entry contradicts a designer's
   correction, fix the entry; never override the designer. A `DOCUMENT` (.md or .txt) needs no
   role: it goes straight into the brand's knowledge.
5. Save right away, in the same turn: call `apply_inbox_classification` with the reference and
   the same entries. Do not ask for confirmation first; the user already chose to save these
   files when they pressed *Listo*. The exceptions: if the preview warns that a font would
   replace a family already saved in that role, ask a single yes/no before saving, because the
   old family and its files are removed and cannot be recovered; and if it reports that a
   document would replace existing knowledge fragments, tell the user how many and ask a single
   yes/no (two different documents with the same file name overwrite each other).
6. Then show the list of what was saved, in plain words and without tool names (file, what it
   was saved as, and its description; for fonts family, weight and style), and ask one
   question: "¿Quieres cambiar algo?". The apply answers with a download link per saved file
   (valid for the time it states): use those links for "Local copy" instead of requesting new
   ones, and give one to the user if they want to see a file.
7. If they want a change, make it directly, without another confirmation:
   - An image saved with the wrong role, description or variant: `update_asset`. If that tool
     is not in your list yet, delete it with `delete_asset` and save it again through the panel.
   - A file they did not want: `delete_asset` (or `discard_inbox_items` if it was never saved).
   - A font with the wrong family, weight or style: open the panel again with
     `open_upload_inbox`, ask them to drop that file once more and correct it there, then save
     it as in steps 3 to 5.
   Then show the updated item and ask "¿Algo más?" until they say no. Anything left unclassified
   in the inbox expires after 24 hours.

## Documents (brand knowledge)

This is the canonical rule for documents; other files point here. A document is brand knowledge,
not an asset: it never gets `request_asset_upload` or a local copy.

- **.md and .txt:** through the upload panel (Option 0). They land in the brand's knowledge as
  the `DOCUMENT` kind.
- **PDF, .pptx, .docx:** the panel rejects them. Ask the user to drag or attach the file into the
  chat; the host extracts the text and you save it with `add_knowledge`.
- **Replace, not add.** Re-uploading a document with the same file name replaces its previous
  knowledge. `add_knowledge` also replaces the entry with the same `sourceLabel`. Use one stable
  `sourceLabel` per topic, never reuse a label for a different topic, and to extend a topic send
  the previous content plus the new one. Before replacing, read the labels with `list_knowledge`.

## Option 1: upload in the browser

The recommended route when the upload panel is not available.


1. Request the link, check it as above, then open it in Chrome for the user:
   `open -a "Google Chrome" "<uploadUrl>"`. If Chrome cannot be opened, give the link as plain
   text instead.
2. Tell the user, in plain steps: "Te abrí la página para subir el archivo. Toca *Elegir
   archivo*, selecciona el archivo y toca *Subir*. Cuando diga *Uploaded*, vuelve aquí". The
   form picks a file from the computer, not the chat attachment.
3. When they say it is done, confirm with `list_assets` that it shows as ready. If it is not,
   request a new link once and open it again.

This leaves no local copy; a piece gets one with "Local copy" when it needs the file.

## Option 2: upload from the project's own folders (decodex-sync only)

Used only by `decodex-sync`, which takes each path from the project's own folders (the assets
folder, `foundations/`, `frameworks/`). Never ask the user where a file is saved, never look for
files elsewhere on the computer, and never offer this option in any other flow: a file the person
wants to add goes through Option 0 or Option 1, and an image only attached to the conversation is
not a file (you may read colors from it, but you cannot upload it).

1. Request the link, check it as above, and upload: `curl -fsS -F "file=@<path>" "<uploadUrl>"`.
   If Desktop asks permission to read outside the project folder, tell the user to accept it.
   Batch: one `-F "files=@<path>"` per file, in the same order as the descriptions.
2. Confirm with `list_assets` that it shows as ready. Never show the link or curl's output to
   the user.
3. No copy is made here: the files already live in the project, and a piece verifies its copy
   with "Local copy" before using it.
4. If curl fails or the link expired: request a new link once. If it fails again, go to
   Option 1 without making the user repeat anything.

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
5. When they say it is done, confirm with `get_brand_fonts` that the weights appear. Its local
   copy is downloaded with "Local copy" when a piece needs it.
6. Use `add_brand_font` only as a fallback when the links cannot be used: say first that it
   takes several minutes and continue only after a clear yes.

## Local copy (a verified cache of Decodex)

Decodex is the only source of brand files. The assets folder (`library/` or `resources/`, see
`structure-and-assets.md`) is just a cache of what Decodex gave this computer: never put a file
there from anywhere else, and never use a file in it that was not verified as below.

**Before each piece, for every asset it uses** (logo, image, icon, font file), silently:

1. Read the expected hash: `get_asset` with the asset id (from `list_assets` or `search_assets`)
   returns the file's `sha256`. For a font file, use the `sha256` that `get_brand_fonts` or
   `get_asset` gives for it; when neither gives one, treat the copy as different.
2. Hash the local copy with `sha256sum "<file>"` or, where that does not exist,
   `shasum -a 256 "<file>"` (the first field of the output).
3. The file is missing, or its hash differs from the expected one, or you cannot tell which local
   file is this asset's: download it again (below), replacing the old file, and hash it once more.
   If the new hash still differs, request a new link once; if it still differs, stop with a plain
   sentence ("No pude preparar este archivo de la marca. Inténtalo de nuevo en un momento.") and
   do not use any copy of it.
4. The hashes are equal: use the file as is.

Say nothing about the check. If something has to be downloaded and the wait is noticeable, one
line is enough: "Dame un momento, preparo los archivos de la marca."

**Download:**

1. Call `get_asset_download_url` with the asset id and check the link as above. It is valid for
   the time the tool states, so request it right before downloading.
2. `curl -fsS -o "<assets>/<type>/<name>" "<downloadUrl>"`. The server names the file by its id,
   so choose `<name>` yourself the first time: a short kebab-case name from the asset's
   description plus the extension of its type (`logo-main-blue-on-yellow.png`), and keep the same
   name on later downloads. Never show the link or curl's output to the user.
3. If it fails, request a new link once. If it fails again, stop as in step 3 above. Never ask
   where the file is saved on the computer and never copy it from anywhere else.

An uploaded font works the same way, with its link from `get_brand_fonts` instead: one link per
weight and style, valid 60 minutes (call it again for fresh ones). Check each link as above and
save it as `<assets>/fonts/<family>-<weight>-<style>.<ext>` (`souvenir-std-700-normal.woff2`),
with the extension of the uploaded file (.ttf, .otf, .woff or .woff2). A font from Google Fonts
has no file: the HTML links it instead.

**A file that is not in Decodex.** If an asset a piece needs does not exist in Decodex, say so
and offer to upload it; do not look for it anywhere else. Example: "Esta tipografía no está en
Decodex. ¿La subimos?" Upload it with Option 0 or Option 1, then download it with this section.
