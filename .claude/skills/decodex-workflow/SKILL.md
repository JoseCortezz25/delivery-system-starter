---
name: decodex-workflow
description: Entry point of every Decodex brand session. Signs in, runs the silent checks, works out once per chat whether the person came to produce pieces or to codify the brand (from the opening message, or with one question), sets the reply format and the order Setup then Production, and hands off to decodex-setup, decodex-production or decodex-sync. Use at the start of every session and whenever the user asks to move between codifying the brand and producing pieces.
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
   ones `list_accessible_brands` shows and switch only to the one they pick (with no lock the project
   has no brand yet, so this picks it; once picked, it stays the project's brand).
2. Sign in first if the chat has not (root `CLAUDE.md`, "Sign in first": `sign_in`, and
   `chatToken` on every call). The person picks the brand inside the sign-in panel, and it must
   be the project's own. Then call `get_brand`. It is the project's brand when its id equals `brand.id`, or, when the lock
   has no id, when its name equals `brand.name` exactly, ignoring case. If it is not, call
   `list_accessible_brands` and look for the project's brand the same way:
   - listed once → ask with the popup before switching: "Este proyecto es de la marca
     <brand.name>, pero ahora estás conectado a <marca actual>. ¿Cambio a <brand.name>?" with
     1) "Sí, cambiar" (recommended) and 2) "No". On yes, change brand to that brand's id (root `CLAUDE.md`,
     "Changing brand": `switch_brand_in_chat` first), then `get_brand` again to confirm. On no, stop and say this project only works with
     <brand.name>. Do not work on another brand;
     a request for any other brand later in the chat is not switched either (root `CLAUDE.md`, "Changing brand");
   - listed more than once (same name) → ask which one, showing each brand's name and id;
   - not listed and the lock has a `brand.id` → the brand exists but this user cannot reach it:
     stop and say: "Tu usuario no tiene acceso a la marca <brand.name> en Decodex. Pídele
     acceso a tu administrador." Do not work on another brand;
   - not listed and the lock has no `brand.id` → the brand may not exist yet. Ask with the popup:
     "No encuentro la marca <brand.name> en Decodex. ¿La creo con ese nombre?" with 1) "Sí,
     crearla" (recommended) and 2) "No". On yes, `create_brand` with `brand.name` (this is the project's own brand, so this chat does switch
     to it), then change brand to the new id (root `CLAUDE.md`, "Changing brand") and `get_brand` to confirm. On no,
     or on a permission error, stop with the sentence of the case above. Never create a brand
     with another name, and never create one when the lock has a `brand.id`.
3. Call `get_brand_setup_status`. If any call fails, go to "Connection errors".

### Start of a chat: produce or codify (once per chat)

After the checks above, work out the person's intent **once per chat**. First match the opening
message of the chat, loosely (ignore case and accents; `<X>` is the brand name). The Decodex
plugin pre-fills these:

| Opening message | Intent |
|---|---|
| "Hola, quiero codificar la marca <X>" | codify: invoke `decodex-setup` |
| "Hola, quiero producir piezas de la marca <X>" | produce: `decodex-production` |
| "Hola, ya actualicé el proyecto de la marca <X>. Quiero iniciar sesión y sincronizar." | sign in, run the sync path below, then ask the question below |
| "Hola, empecemos a configurar la marca <X>" (older plugin) | codify: invoke `decodex-setup` |

If the opening message is none of these but already makes the intent clear ("quiero hacer un
banner" is produce; "quiero subir los logos" is codify), use it. Otherwise greet by the brand's
name and ask, with the popup, header "Inicio": "¿Qué quieres hacer?" with 1) "Producir piezas"
and 2) "Codificar la marca". Recommend 2 while the brand is not ready to produce (`decodex-production`
B1), 1 once it is. Seeing or changing what is already saved is part of 2 (read it back with the
`get_*` tools; changes go through `decodex-setup`). Do not open with a status report.

- **Ask at most once per chat.** Never repeat the question later in the same chat, not even
  after a new sign-in because the 8 hours ran out: sign in again and resume what the person was
  doing. If the person later asks to switch task ("ahora quiero producir", "mejor configuremos
  los colores"), do it, subject to their role (root `CLAUDE.md`, "Roles").
- **Role.** The person's role on this brand comes from the sign-in or `switch_brand_in_chat`
  result when it states it. Codify as a Maker: say "En esta marca puedes producir piezas, pero
  no codificarla. Pídele permiso a tu administrador." and offer to produce instead. When the
  result does not state the role, do not guess: go ahead and answer a permission refusal the same
  way (root `CLAUDE.md`, "Roles").
- **Old project with local brand information** (the sync trigger below). A Codifier or
  administrator: offer `decodex-sync` and invoke it on yes. A Maker, or a permission refusal on
  that offer: say "Este proyecto tiene información de la marca que todavía no está en Decodex.
  Pídele a quien codifica la marca que abra este proyecto para pasarla." and allow producing
  only when the brand in Decodex is already codified (`decodex-production` B1). When the role is not stated, decide it with the silent
  check in `decodex-sync`, step 4, before offering anything.

**Sync trigger.** If `foundations/` or `frameworks/` hold Markdown content and there is no
`.decodex-sync.json` at the project root, the local brand data can be passed to Decodex once.
Offer it too when the assets folder (`structure-and-assets.md`) holds a logo, image or font file that Decodex
does not have yet (no `list_assets` description with `(archivo: <file name>)`, or the font's
weight missing from `get_brand_fonts`), even with the marker: `decodex-sync` then uploads only
those files. Any request to pass, sync or send the local brand base, templates or files to the
brand again ("pasa otra vez la información a la marca") also goes to `decodex-sync`, which answers
it; never offer to redo it or to overwrite the brand from the local copies yourself. The sync
opening message goes straight to `decodex-sync` (it still asks for the brand confirmation), then
continues with the question above.

A brand is ready to produce when setup status shows no gaps (logo, fonts, colors, tone and
frameworks), which means at least one framework is saved.

Roles: the server decides permissions (root `CLAUDE.md`, "Roles"). A Maker never changes brand
rules; a Codifier curates the brand and can also produce, but does not mass-produce. If a tool
says the action is not allowed, say so in plain words, point to their administrator, and never
work around it.

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

## Session summary (mandatory)

Decodex keeps a record of every session so the team can see what worked and what to improve.
When `save_session_summary` is in your tool list, call it after every user request, as the
last step of that request, whether it ended well, partly, blocked or abandoned:

- `userGoal`: what the user asked for, in their own words, short.
- `actionsTaken`: what you did, in plain words (no tool names or ids).
- `result`: `COMPLETED`, `PARTIAL`, `BLOCKED` or `ABANDONED`.
- `friction` (when there was any): what got in the way: an error, a retry, a misunderstanding,
  something the user had to repeat.
- `improvementIdeas` (when you have one): what would have made it easier.

It is silent: never mention it to the user, never ask permission for it, and never let it
change your reply. If it fails, continue as if nothing happened. One request can end in
several turns; call it once when the request is done or the user moves on to something else.

## Connection errors

If a tool says the person must sign in, or its sign-in is no longer valid, call `sign_in` and
retry once (root `CLAUDE.md`, "Sign in first"). If a tool fails or is unavailable: stop, say it in plain words, do not invent values and do
not save locally instead. Options: 1) retry (log in again: tell the user, in plain words, to
open `/mcp`, choose Decodex and sign in), 2) consult only what is already
in `engine/`, `content/` and `references/` (`foundations/` and `frameworks/` only
while the project is not locked; never once `.decodex-sync.json` exists), nothing saved and
no new piece (its files cannot be verified without Decodex),
3) stop here.

Missing mandatory data (for example fonts): "Esta tipografía no está en Decodex." Options:
1) upload the font file (`decodex-asset-upload`), 2) leave it for later. Never use a font or any
other input from the person's computer.
