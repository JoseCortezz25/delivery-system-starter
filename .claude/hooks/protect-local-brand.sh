#!/usr/bin/env bash
# PreToolUse (Read|Glob|Grep|Write|Edit|MultiEdit|NotebookEdit): dormant until the decodex-sync skill
# syncs foundations/ and frameworks/ to Decodex and writes the sync marker (.decodex-sync.json) at the
# project root. While the marker is absent this hook allows everything, silently. Once it exists, the
# two folders are a synced, locked local baseline and the AI may not read, search or change them: the brand
# data lives in Decodex. Shell access to them is handled by block-protected-delete.sh.
# Matching is case-insensitive (macOS file systems are case-insensitive by default); paths are checked
# both as written (with . and .. folded) and after resolving symlinks.
# Written for bash 3.2 (macOS default): no ${var,,}, no associative arrays, no mapfile.

# deny REASON: prints the PreToolUse deny decision; backslashes and double quotes in REASON are
# escaped so the JSON stays valid.
deny() {
  local m=$1
  m=${m//\\/\\\\}
  m=${m//\"/\\\"}
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$m"
  exit 0
}

FROZEN="foundations/ and frameworks/ are frozen: this project was synced to Decodex (.decodex-sync.json), so the AI may not read, search or change them. The brand data lives in Decodex: read it with get_foundations, get_brand_colors, get_brand_fonts, get_brand_voice, list_frameworks and get_framework. Framework drafts are kept in a temporary file outside the project."
SCOPE="Scope the search to a specific folder that is not frozen (for example engine/, content/, library/ or references/) with the path parameter, and keep foundations, frameworks and .. out of the pattern."
# What Claude may say to the user after each kind of denial: one plain Spanish sentence, never the
# file, the folder or this block (the user is a designer; see CLAUDE.md, "Talking to the user").
TELL_READ='Tell the user only, in Spanish: "Esa información ya está guardada en la marca, así que la consulto directamente desde ahí." Then read it with get_foundations / get_brand_colors / get_framework. Never mention files, folders or this block.'
TELL_CHANGE='Tell the user only, in Spanish: "Esa información ya está guardada en la marca y aquí no se puede cambiar ni borrar. Si quieres cambiar algo, lo hago directamente en la marca." Then make the change in the brand with the setup tools, only if the user asks for it. Never mention files, folders or this block.'
TELL_SEARCH='Say nothing to the user about this block: scope the search to engine/, content/, library/ or references/ and continue. If you need brand data, read it with get_foundations / get_brand_colors / get_framework. Never mention files, folders or this block.'

input=$(cat 2>/dev/null)

# shellcheck source=/dev/null
. "$(dirname -- "${BASH_SOURCE[0]}")/guard-lib.sh" 2>/dev/null && [ -n "${GUARD_SYNC_MARKER:-}" ] \
  || deny "The list of protected project files could not be loaded, so this file access cannot be checked. Ask the user to check .claude/hooks/. See RULES.md."

# Dormant while the project has not been synced.
if [ ! -e "$GUARD_PROJ/$GUARD_SYNC_MARKER" ] && [ ! -L "$GUARD_PROJ/$GUARD_SYNC_MARKER" ]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  deny "jq is not installed, so file access cannot be checked against the frozen brand folders. Install jq (for example: brew install jq) and try again. See RULES.md."
fi

fields=$(printf '%s' "$input" | jq -r '[
    (.tool_name // ""),
    (.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // ""),
    (.tool_input.pattern // ""),
    (.tool_input.glob // ""),
    (.cwd // "")
  ] | map(gsub("[\n\r]"; " ")) | .[]' 2>/dev/null) \
  || deny "This tool call could not be read to check it against the frozen brand folders. See RULES.md."
{
  IFS= read -r tool
  IFS= read -r target
  IFS= read -r pattern
  IFS= read -r glob
  IFS= read -r cwd
} <<< "$fields"
[ -n "$tool" ] || deny "This tool call could not be read to check it against the frozen brand folders. See RULES.md."
[ -n "$cwd" ] || cwd=$GUARD_PROJ

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# fold PATH: lexically folds "." and ".." components of an absolute path.
fold() {
  local IFS='/' part out=""
  local -a parts
  read -r -a parts <<< "$1"
  for part in "${parts[@]}"; do
    case "$part" in
      '' | .) ;;
      ..) out=${out%/*} ;;
      *) out="$out/$part" ;;
    esac
  done
  printf '%s' "${out:-/}"
}

# absolute PATH: makes PATH absolute against the tool call's working directory (~ is the home folder).
absolute() {
  local p=$1
  case "$p" in
    '~') p=$HOME ;;
    '~/'*) p="$HOME/${p#\~/}" ;;
  esac
  case "$p" in /*) ;; *) p="$cwd/$p" ;; esac
  fold "$p"
}

# resolve PATH: physical path of the nearest existing parent, plus the remaining components; follows
# a symlink at the path itself (a few levels).
resolve() {
  local p d rest n=0 t
  p=$(absolute "$1")
  while [ -L "$p" ] && [ "$n" -lt 10 ]; do
    t=$(readlink -- "$p") || break
    case "$t" in /*) p=$(fold "$t") ;; *) p=$(fold "$(dirname -- "$p")/$t") ;; esac
    n=$((n + 1))
  done
  if [ -d "$p" ]; then
    (cd -- "$p" 2>/dev/null && pwd -P) || printf '%s' "$p"
    return
  fi
  d=$(dirname -- "$p")
  rest="/$(basename -- "$p")"
  while [ ! -d "$d" ] && [ "$d" != "/" ]; do
    rest="/$(basename -- "$d")$rest"
    d=$(dirname -- "$d")
  done
  d=$(cd -- "$d" 2>/dev/null && pwd -P) || d=$(dirname -- "$p")
  fold "${d%/}$rest"
}

root=$(cd -- "$GUARD_PROJ" 2>/dev/null && pwd -P) || root=$GUARD_PROJ
root_lc=$(lower "$(fold "$root")")
proj_lc=$(lower "$(fold "$GUARD_PROJ")")

# in_brand PATH_LC: true when the lowercased absolute path is one of the frozen folders or inside one.
in_brand() {
  local r d
  for r in "$root_lc" "$proj_lc"; do
    for d in $GUARD_BRAND_DIRS; do
      case "$1" in "$r/$d" | "$r/$d/"*) return 0 ;; esac
    done
  done
  return 1
}

# contains_brand PATH_LC: true when the path is the project root, an ancestor of it (so a search there
# would reach the frozen folders), or a frozen folder or something inside one.
contains_brand() {
  local r
  in_brand "$1" && return 0
  for r in "$root_lc" "$proj_lc"; do
    [ "$1" = "/" ] && return 0
    case "$r" in "$1" | "$1/"*) return 0 ;; esac
  done
  return 1
}

# names_brand TEXT: true when a glob or pattern text names a frozen folder or climbs with "..".
names_brand() {
  local t d
  t=$(lower "$1")
  for d in $GUARD_BRAND_DIRS; do
    case "$t" in *"$d"*) return 0 ;; esac
  done
  case "/$t/" in */../*) return 0 ;; esac
  return 1
}

# glob_base GLOB: the leading components of an absolute glob that hold no wildcard.
glob_base() {
  local IFS='/' part out=""
  local -a parts
  read -r -a parts <<< "$1"
  for part in "${parts[@]}"; do
    case "$part" in *[*?[{]*) break ;; '') ;; *) out="$out/$part" ;; esac
  done
  printf '%s' "${out:-/}"
}

case "$tool" in
  Read | Write | Edit | MultiEdit | NotebookEdit)
    [ -n "$target" ] || exit 0
    if in_brand "$(lower "$(absolute "$target")")" || in_brand "$(lower "$(resolve "$target")")"; then
      if [ "$tool" = "Read" ]; then deny "$FROZEN See RULES.md. $TELL_READ"; fi
      deny "$FROZEN See RULES.md. $TELL_CHANGE"
    fi ;;
  Glob | Grep)
    if [ -z "$target" ]; then
      deny "This search has no path, so it would cover the whole project, including the frozen foundations/ and frameworks/. $SCOPE $FROZEN See RULES.md. $TELL_SEARCH"
    fi
    if contains_brand "$(lower "$(absolute "$target")")" || contains_brand "$(lower "$(resolve "$target")")"; then
      deny "This search covers the frozen foundations/ or frameworks/ (its path is the project root, a folder above it, or one of them). $SCOPE $FROZEN See RULES.md. $TELL_SEARCH"
    fi
    globs=$glob
    [ "$tool" = "Glob" ] && globs=$pattern
    if [ -n "$globs" ]; then
      if names_brand "$globs"; then
        deny "This search pattern names the frozen foundations/ or frameworks/, or climbs out of its folder with '..'. $SCOPE $FROZEN See RULES.md. $TELL_SEARCH"
      fi
      case "$globs" in
        '~') globs=$HOME ;;
        '~/'*) globs="$HOME/${globs#\~/}" ;;
      esac
      case "$globs" in
        /*)
          base=$(glob_base "$globs")
          if contains_brand "$(lower "$(fold "$base")")" || contains_brand "$(lower "$(resolve "$base")")"; then
            deny "This search pattern is an absolute path that covers the frozen foundations/ or frameworks/. $SCOPE $FROZEN See RULES.md. $TELL_SEARCH"
          fi ;;
      esac
    fi ;;
esac
exit 0
