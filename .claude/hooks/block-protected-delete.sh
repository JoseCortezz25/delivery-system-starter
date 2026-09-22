#!/usr/bin/env bash
# PreToolUse(Bash) guard. Policy (see RULES.md):
#   - Protected harness files (CLAUDE.md, RULES.md, .mcp.json, .gitignore, anything in .claude/)
#     are never deleted, moved away, truncated, or overwritten by a shell redirect (Write/Edit on
#     them is blocked separately by protect-claude-dir.sh).
#   - Project folders are never deleted or moved away. Deleting a single file inside them is fine.
command=$(jq -r '.tool_input.command // empty')

deny() {
  jq -cn --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# --- Protected files: rm/mv/git rm/truncate/redirect-overwrite -------------------------------
pre='(^|[[:space:]"'"'"'/])'
post='($|[[:space:]"'"'"'/;|&)])'
for name in CLAUDE.md RULES.md .mcp.json .gitignore .claude; do
  esc_name=$(printf '%s' "$name" | sed 's/\./\\./g')
  token="${pre}${esc_name}${post}"
  if echo "$command" | grep -qE "(^|[^[:alnum:]_-])(rm|mv|git[[:space:]]+rm|truncate)[^|;&]*${token}" \
    || echo "$command" | grep -qE ">{1,2}[[:space:]]*(\./)?${esc_name}${post}"; then
    deny "The AI may not modify, delete, move, truncate, or overwrite $name — it is a protected harness file. See RULES.md."
  fi
done

# --- Project folders: never deleted or moved away --------------------------------------------
folders='\.claude|foundations|frameworks|resources|content|knowledge|engine|references'
root="${CLAUDE_PROJECT_DIR:-$PWD}"

# One command per line (split on ; && || | and newlines).
segments=$(printf '%s\n' "$command" | sed -E 's/(&&|\|\||;|\|)/\n/g')

while IFS= read -r seg; do
  read -ra words <<<"$seg"
  [ "${#words[@]}" -eq 0 ] && continue
  i=0
  [ "${words[0]}" = "sudo" ] && i=1
  cmd="${words[$i]}"
  mode=""
  case "$cmd" in
    rm) mode=rm ;;
    rmdir) mode=rmdir ;;
    mv) mode=mv ;;
    git) [ "${words[$((i + 1))]}" = "rm" ] && { mode=rm; i=$((i + 1)); } ;;
  esac
  [ -z "$mode" ] && continue

  recursive=0
  [ "$mode" = "rmdir" ] && recursive=1
  args=()
  for w in "${words[@]:$((i + 1))}"; do
    case "$w" in
      --recursive) recursive=1 ;;
      --*) ;;
      -*) [[ "$w" == *[rR]* ]] && recursive=1 ;;
      *) args+=("$w") ;;
    esac
  done

  # For mv, the last argument is the destination — moving INTO a folder is fine.
  if [ "$mode" = "mv" ] && [ "${#args[@]}" -gt 0 ]; then
    unset 'args[${#args[@]}-1]'
  fi

  for a in "${args[@]}"; do
    p=${a//\"/}; p=${p//\'/}
    p=${p#"$root/"}
    while [[ "$p" == ./* ]]; do p=${p#./}; done
    if [ "$mode" = "mv" ]; then
      # Moving the folder itself away.
      echo "$p" | grep -qE "^(${folders})/?$" \
        && deny "The AI must never move a project folder ($p). See RULES.md."
    elif [ "$recursive" -eq 1 ]; then
      # Recursive delete of a project folder, a folder inside one, or the whole project.
      echo "$p" | grep -qE "^((${folders})(/.*)?|\.|\.\.|\*|/)$" \
        && deny "The AI must never delete folders ($p). Delete individual files instead. See RULES.md."
    fi
  done
done <<<"$segments"

exit 0
