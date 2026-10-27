#!/usr/bin/env bash
# PreToolUse (Bash): snapshot the protected harness set before every shell command so that
# guard-verify.sh can restore it afterwards. It never blocks a command, except when the snapshot
# cannot be taken (so verification can never be skipped silently) or when an earlier command in this
# session changed protected files without being verified (interrupted, or its post-check never ran).
set -u

# shellcheck source=/dev/null
. "$(dirname -- "${BASH_SOURCE[0]}")/guard-lib.sh" || {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "The integrity check for protected harness files could not start, so shell commands are paused. Ask the user to check .claude/hooks/. See RULES.md."
  exit 0
}

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$(guard_json_escape "$1")"
  exit 0
}

fail() {
  deny "The protected harness files could not be snapshotted before this command, so it was not run (the change check cannot be skipped). Ask the user to check the project folder permissions. See RULES.md."
}

input=$(cat 2>/dev/null)
session=""
re='"session_id"[[:space:]]*:[[:space:]]*"([^"]*)"'
[[ $input =~ $re ]] && session=${BASH_REMATCH[1]}

[ -d "$GUARD_STATE" ] || mkdir -p -- "$GUARD_STATE" 2>/dev/null || fail

# A previous command of this session was never verified: check it now, before taking a new baseline.
if [ -f "$GUARD_STATE/pending" ] && [ -f "$GUARD_STATE/manifest" ] && [ -f "$GUARD_STATE/snap.tar" ] \
  && [ "$(<"$GUARD_STATE/pending")" = "$session" ]; then
  guard_check_and_restore
  case $? in
    0)
      rm -f -- "$GUARD_STATE/pending"
      deny "A previous command changed protected harness files (${GUARD_CHANGED}). They were restored. The AI may not modify them; if the user wants this change, ask them to run it themselves with \`!\`." ;;
    2)
      deny "A previous command changed protected harness files (${GUARD_CHANGED:-unknown}) and they could not be fully restored. Ask the user to check them before continuing. See RULES.md." ;;
  esac
fi

manifest=$(guard_manifest) || fail

# Trusted copy of the hooks, taken from the snapshot baseline. settings.json runs the hooks from this
# copy first, so a command that edits or deletes .claude/hooks/ cannot disable its own check.
refresh_bin() {
  local src="$GUARD_PROJ/.claude/hooks" tmp="$GUARD_STATE/bin.$$"
  [ -d "$src" ] || return 0
  rm -rf -- "$tmp" && mkdir -p -- "$tmp" && cp -p -- "$src"/*.sh "$tmp"/ 2>/dev/null \
    && rm -rf -- "$GUARD_STATE/bin" && mv -- "$tmp" "$GUARD_STATE/bin" || rm -rf -- "$tmp"
}

if [ -f "$GUARD_STATE/snap.tar" ] && [ -f "$GUARD_STATE/manifest" ] \
  && [ "$manifest" = "$(<"$GUARD_STATE/manifest")" ]; then
  [ -d "$GUARD_STATE/bin" ] || refresh_bin
  printf '%s' "$session" > "$GUARD_STATE/pending" || fail
  exit 0
fi

guard_paths
tmp_tar="$GUARD_STATE/snap.tar.$$"
tmp_man="$GUARD_STATE/manifest.$$"
if [ "${#GUARD_PATHS[@]}" -gt 0 ]; then
  tar -cf "$tmp_tar" -C "$GUARD_PROJ" "${GUARD_PATHS[@]}" 2>/dev/null || { rm -f -- "$tmp_tar"; fail; }
else
  tar -cf "$tmp_tar" -T /dev/null 2>/dev/null || { rm -f -- "$tmp_tar"; fail; }
fi
printf '%s\n' "$manifest" > "$tmp_man" || { rm -f -- "$tmp_tar" "$tmp_man"; fail; }
mv -f -- "$tmp_tar" "$GUARD_STATE/snap.tar" && mv -f -- "$tmp_man" "$GUARD_STATE/manifest" || fail
refresh_bin
printf '%s' "$session" > "$GUARD_STATE/pending" || fail
exit 0
