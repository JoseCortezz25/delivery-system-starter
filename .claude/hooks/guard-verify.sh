#!/usr/bin/env bash
# PostToolUse / PostToolUseFailure (Bash): compare the protected harness set with the snapshot taken
# by guard-snapshot.sh. If the command changed it (modified, deleted or new files under .claude/, or
# a protected root file created or deleted), restore the snapshot exactly and tell the AI. Silent
# when nothing changed.
set -u

emit() { # emit REASON
  local r
  r=$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n\t' '  ')
  if [ "$event" = "PostToolUseFailure" ]; then
    printf '{"decision":"block","reason":"%s","hookSpecificOutput":{"hookEventName":"PostToolUseFailure","additionalContext":"%s"}}\n' "$r" "$r"
  else
    printf '{"decision":"block","reason":"%s"}\n' "$r"
  fi
  exit 0
}

input=$(cat 2>/dev/null)
event=""
re='"hook_event_name"[[:space:]]*:[[:space:]]*"([^"]*)"'
[[ $input =~ $re ]] && event=${BASH_REMATCH[1]}

# shellcheck source=/dev/null
. "$(dirname -- "${BASH_SOURCE[0]}")/guard-lib.sh" \
  || emit "The integrity check for protected harness files could not run after this command. Ask the user to check .claude/hooks/ and the protected files."

if [ ! -f "$GUARD_STATE/manifest" ] || [ ! -f "$GUARD_STATE/snap.tar" ]; then
  emit "The protected harness files could not be verified after this command: the integrity snapshot is missing. Ask the user to check CLAUDE.md, RULES.md, .mcp.json, .gitignore, codex-lock.json and .claude/."
fi

guard_check_and_restore
status=$?
rm -f -- "$GUARD_STATE/pending"
case $status in
  0)
    emit "The command changed protected harness files (${GUARD_CHANGED}). They were restored. The AI may not modify them; if the user wants this change, ask them to run it themselves with \`!\`." ;;
  2)
    emit "The command changed protected harness files (${GUARD_CHANGED:-unknown}) and they could not be fully restored. The AI may not modify them; ask the user to check them before continuing." ;;
esac
exit 0
