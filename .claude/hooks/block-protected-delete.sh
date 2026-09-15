#!/usr/bin/env bash
command=$(jq -r '.tool_input.command // empty')

pre='(^|[[:space:]"'"'"'/])'
post='($|[[:space:]"'"'"'/])'

for name in CLAUDE.md RULES.md .mcp.json .gitignore .claude; do
  esc_name=$(printf '%s' "$name" | sed 's/\./\\./g')
  token="${pre}${esc_name}${post}"
  if echo "$command" | grep -qE "(rm|mv|git[[:space:]]+rm|truncate)[^|;&]*${token}" \
    || echo "$command" | grep -qE ">{1,2}[[:space:]]*${esc_name}${post}"; then
    if [ "$name" = ".claude" ]; then
      reason="The AI is not allowed to modify or delete .claude/ via shell commands — it is the protected harness configuration. See RULES.md."
    else
      reason="The AI is not allowed to modify or delete $name via shell commands — it is a protected project file. See RULES.md."
    fi
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"$reason\"}}"
    exit 0
  fi
done
