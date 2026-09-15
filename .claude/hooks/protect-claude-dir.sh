#!/usr/bin/env bash
file=$(jq -r '.tool_input.file_path // empty')
base=$(basename -- "$file")
case "$file" in
  */.claude/*|.claude/*)
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"The AI is not allowed to create or edit files inside .claude/ — it is the protected harness configuration (hooks, skills, knowledge, rules, settings). See RULES.md."}}'
    exit 0
    ;;
esac
case "$base" in
  CLAUDE.md|RULES.md|.mcp.json|.gitignore)
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"The AI is not allowed to modify $base — it is a protected project file. See RULES.md.\"}}"
    ;;
esac
