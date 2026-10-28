---
name: decodex-workflow
description: Entry point of every Decodex brand session. Runs the silent checks, shows the router (configure the brand, create a piece, review what is saved), sets the reply format and the order Setup then Production, and hands off to decodex-setup or decodex-production. Use at the start of every session and whenever the user moves between configuring the brand and producing pieces.
compatibility: Requires the decodex-brand MCP connection.
metadata:
  version: "0.1.0"
---

# Decodex workflow

How to talk to the user (tone, vocabulary, synonyms) lives in the root `CLAUDE.md`. This skill
decides where the session goes; `decodex-setup` and `decodex-production` do the work.

## Reply format (every turn, in Spanish)

1. **Where we are** — one sentence of plain text: what was just done, or the current stage.
2. **One question, asked with the `AskUserQuestion` popup** with 2-4 options. Never an open
   blank-page question. Put the recommended option first and end its label with
   "(Recomendada)". The popup already offers "Otro" for free text, so never add it yourself.
   Keep the header short (12 characters max).
3. **Next step** — one line of plain text before the popup: "Lo siguiente: ...".

One question per turn: after calling the popup, stop and wait for the answer. Never name
tools, folders or files to the user. If the popup is not available in this client, ask the
same question as a numbered list in plain text and stop.

## Router (silent)

1. Read `codex-lock.json` at the project root (its fields are in `structure-and-assets.md`):
   `brand.id` when present, and `brand.name`. That is the brand this project belongs to. If there
   is no `codex-lock.json` (the template itself or an older project), skip the comparison in
   step 2: use the brand `get_brand` returns, and if the user says it is not theirs, offer the
   ones `list_accessible_brands` shows and switch only to the one they pick.
2. Call `get_brand`. It is the project's brand when its id equals `brand.id`, or, when the lock
   has no id, when its name equals `brand.name` exactly, ignoring case. If it is not, call
   `list_accessible_brands` and look for the project's brand the same way:
   - listed once → ask with the popup before switching: "Este proyecto es de la marca
     <brand.name>, pero ahora estás conectado a <marca actual>. ¿Cambio a <brand.name>?" with
     1) "Sí, cambiar" (recommended) and 2) "No". On yes, `switch_brand` with that brand's id,
     then `get_brand` again to confirm. On no, stop and say this project only works with
     <brand.name>. Do not work on another brand;
   - listed more than once (same name) → ask which one, showing each brand's name and id;
   - not listed → stop and say: "Tu usuario no tiene acceso a la marca <brand.name> en
     Decodex. Pídele acceso a tu administrador." Do not work on another brand.
3. Call `get_brand_setup_status`. If any call fails, go to "Connection errors".

Greet by the brand's name and ask, with the popup:

1. "Configurar mi marca" → invoke `decodex-setup`
2. "Crear una pieza" → invoke `decodex-production`
3. "Ver o cambiar lo ya guardado" → read it back with the `get_*` tools; changes go through
   `decodex-setup`

If `foundations/` or `frameworks/` hold Markdown content and there is no `.decodex-sync.json`
at the project root, the local brand data can be passed to Decodex once: offer it and invoke
`decodex-sync` on yes. Any request to pass, sync or send the local brand base or templates to the
brand again ("pasa otra vez la información a la marca") also goes to `decodex-sync`, which answers
it; never offer to redo it or to overwrite the brand from the local copies yourself.

Recommend 1 while the brand is not ready to produce, 2 once it is. A brand is ready when setup
status shows no gaps (logo, fonts, colors, tone and frameworks), which means at least one
framework is saved. Do not open with a status report.

Roles: the server decides permissions. A Maker never changes brand rules; a Codifier
configures and does not mass-produce. If a tool says the action is not allowed, say so in
plain words, point to their administrator, and never work around it.

## Order

Setup comes before Production, always. Inside Setup: colors, fonts and logo; then tone; then
frameworks; then the test piece and its approval. Never start a framework while colors, fonts
or logo are missing, and never produce while no framework is saved.

## Never hardcode a brand value

Every color, font, voice rule and framework value comes from a Decodex read. If one is
missing, go back to the Setup gap; never write it into any file: a script, an HTML piece or a
framework. Colorways: `add_knowledge`.

## Deleting

Before any `delete_*` tool, list what exists (`list_assets`, `list_knowledge`,
`list_products`, `get_foundations`), say plainly what will be removed, and delete only after a
clear yes. A delete cannot be undone.

## Connection errors

If a tool fails or is unavailable: stop, say it in plain words, do not invent values and do
not save locally instead. Options: 1) retry (log in again), 2) consult only what is already
in the local folders (never `foundations/` or `frameworks/` once they are locked), nothing
saved, 3) stop here.

Missing mandatory data (for example fonts): "Falta la tipografía oficial." Options: 1) upload
the font file, 2) use a system font only for this test (not saved to the brand).
