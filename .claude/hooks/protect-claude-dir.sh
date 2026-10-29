#!/usr/bin/env bash
# PreToolUse (Write|Edit|MultiEdit|NotebookEdit): the AI may not create or edit the protected harness
# files (CLAUDE.md, RULES.md, .mcp.json, .gitignore, codex-lock.json) or anything inside .claude/.
# Matching is case-insensitive (macOS file systems are case-insensitive by default), and the path is
# also checked after resolving symlinks, so a link pointing into .claude/ does not get around it.

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

if ! command -v jq >/dev/null 2>&1; then
  deny "jq is not installed, so file edits cannot be checked against the protected project files. Install jq (for example: brew install jq) and try again. See RULES.md."
fi

file=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' 2>/dev/null) \
  || deny "The file path of this edit could not be read to check it against the protected project files. See RULES.md."
[ -n "$file" ] || exit 0

check() {
  local path lc base
  path=$1
  lc=$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')
  case "$lc" in
    */.claude/* | .claude/* | */.claude | .claude)
      deny "The AI is not allowed to create or edit files inside .claude/ — it is the protected harness configuration (hooks, skills, knowledge, rules, settings). See RULES.md." ;;
  esac
  base=$(basename -- "$lc")
  case "$base" in
    claude.md | rules.md | .mcp.json | .gitignore | codex-lock.json)
      deny "The AI is not allowed to modify $(basename -- "$path") — it is a protected project file. See RULES.md." ;;
  esac
}

# resolve PATH: physical path of the nearest existing parent, plus the remaining components; follows
# a symlink at the file itself (a few levels).
resolve() {
  local p=$1 d rest="" n=0 t
  case "$p" in /*) ;; *) p="${CLAUDE_PROJECT_DIR:-$PWD}/$p" ;; esac
  while [ -L "$p" ] && [ "$n" -lt 10 ]; do
    t=$(readlink -- "$p") || break
    case "$t" in /*) p=$t ;; *) p="$(dirname -- "$p")/$t" ;; esac
    n=$((n + 1))
  done
  d=$(dirname -- "$p")
  rest="/$(basename -- "$p")"
  while [ ! -d "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ]; do
    rest="/$(basename -- "$d")$rest"
    d=$(dirname -- "$d")
  done
  d=$(cd -- "$d" 2>/dev/null && pwd -P) || d=$(dirname -- "$p")
  printf '%s%s' "${d%/}" "$rest"
}

check "$file"
check "$(resolve "$file")"
exit 0
