#!/usr/bin/env bash
# PreToolUse (Bash): best-effort first barrier against shell commands that modify the protected
# harness files (CLAUDE.md, RULES.md, .mcp.json, .gitignore, codex-lock.json and .claude/).
# It only gives an early, readable denial for the obvious cases. The real control is the integrity
# guard (guard-snapshot.sh + guard-verify.sh), which restores anything a command changed anyway.
# Written for bash 3.2 (macOS default): no ${var,,}, no associative arrays, no mapfile.

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

if ! command -v jq >/dev/null 2>&1; then
  deny "jq is not installed, so shell commands cannot be checked against the protected project files. Install jq (for example: brew install jq) and try again. See RULES.md."
fi

command=$(jq -r '.tool_input.command // empty' 2>/dev/null) \
  || deny "The shell command could not be read to check it against the protected project files. See RULES.md."
[ -n "$command" ] || exit 0

# Names are matched case-insensitively (macOS file systems are case-insensitive by default).
lc=$(printf '%s' "$command" | tr '[:upper:]' '[:lower:]')
proj_lc=$(printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}" | tr '[:upper:]' '[:lower:]')
names="claude.md rules.md .mcp.json .gitignore codex-lock.json .claude"

display_name() {
  case "$1" in
    claude.md) printf 'CLAUDE.md' ;;
    rules.md) printf 'RULES.md' ;;
    *) printf '%s' "$1" ;;
  esac
}

deny_name() {
  if [ "$1" = ".claude" ]; then
    deny "The AI is not allowed to modify or delete .claude/ via shell commands — it is the protected harness configuration. See RULES.md."
  fi
  deny "The AI is not allowed to modify or delete $(display_name "$1") via shell commands — it is a protected project file. See RULES.md."
}

case "$lc" in
  *decodex-guard*)
    deny "The AI is not allowed to touch the harness integrity guard state (decodex-guard). See RULES.md." ;;
esac

# is_protected WORD: true when WORD names a protected path (any path component equal to a protected
# name), or is a glob at the project root that could expand to one (codex-lo*, CLAUDE*, .cla*, *).
# Sets $hit to the matched protected name.
hit=""
is_protected() {
  local w=$1 comp acc="" rootish dots=1 name i
  w=${w//\"/}
  w=${w//\'/}
  w=${w//\\/}
  case "$w" in --*=*) w=${w#*=} ;; esac
  [ -n "$w" ] || return 1
  local IFS='/'
  local -a parts
  read -r -a parts <<< "$w"
  for ((i = 0; i < ${#parts[@]}; i++)); do
    comp=${parts[$i]}
    rootish=0
    if [ "$dots" -eq 1 ] || [ "$acc" = "$proj_lc" ]; then rootish=1; fi
    for name in claude.md rules.md .mcp.json .gitignore codex-lock.json .claude; do
      if [ "$comp" = "$name" ]; then hit=$name; return 0; fi
      case "$comp" in
        *[*?[]*)
          # shellcheck disable=SC2053 # the component is intentionally used as a glob pattern
          if [ "$rootish" -eq 1 ] && [[ $name == $comp ]]; then hit=$name; return 0; fi ;;
      esac
    done
    if [ "$i" -eq 0 ]; then acc=$comp; else acc="$acc/$comp"; fi
    case "$comp" in .|..|'') ;; *) dots=0 ;; esac
  done
  return 1
}

# 1) Redirections (>, >>, >|, &>, &>>) into a protected name.
rest=$lc
re='(&>>|&>|>>|>\||>)[[:space:]]*([^[:space:];&|<>()]+)'
while [[ $rest =~ $re ]]; do
  target=${BASH_REMATCH[2]}
  if is_protected "$target"; then deny_name "$hit"; fi
  rest=${rest#*"${BASH_REMATCH[0]}"}
done

# 2) Split into simple commands (redirections removed) and inspect each command word as a whole word.
stripped=$(printf '%s' "$lc" | sed -E 's/[0-9]*(&>>|&>|>>|>\||>&|>|<)[[:space:]]*[^[:space:];&|<>()]*/ /g')
segments=$(printf '%s\n' "$stripped" | tr ';&|()`' '\n\n\n\n\n\n')

any_protected() { # any_protected ARG...: true when any argument names a protected path
  local a
  for a in "$@"; do
    if is_protected "$a"; then return 0; fi
  done
  return 1
}

check_command() { # check_command WORD...: one simple command, already lowercased
  local -a w=("$@")
  local cmd i n=${#w[@]} last="" a skip_next=0

  # Skip assignments, wrappers and shell keywords to reach the real command word.
  i=0
  while [ "$i" -lt "$n" ]; do
    a=${w[$i]}
    a=${a//\"/}
    a=${a//\'/}
    a=${a#\\}
    case "$a" in
      '' | '{' | '}' | '!' | then | do | else | elif | if | while | until | time | sudo | command | builtin | exec | nohup | nice | eval | '$')
        i=$((i + 1)); continue ;;
      env | xargs)
        i=$((i + 1))
        while [ "$i" -lt "$n" ]; do
          case "${w[$i]}" in -* | *=*) i=$((i + 1)) ;; *) break ;; esac
        done
        continue ;;
      bash | sh | zsh | dash | ksh | */bash | */sh | */zsh)
        i=$((i + 1))
        while [ "$i" -lt "$n" ]; do
          case "${w[$i]}" in -*) i=$((i + 1)) ;; *) break ;; esac
        done
        continue ;;
      [a-z_]*=*)
        case "$a" in *[!a-z0-9_]*=*) ;; *) i=$((i + 1)); continue ;; esac ;;
    esac
    break
  done
  [ "$i" -lt "$n" ] || return 0
  cmd=${w[$i]}
  cmd=${cmd//\"/}
  cmd=${cmd//\'/}
  cmd=${cmd#\\}
  cmd=${cmd##*/}
  local -a args=("${w[@]:$((i + 1))}")
  [ "${#args[@]}" -gt 0 ] || return 0

  case "$cmd" in
    rm | rmdir | unlink | mv | truncate | shred | srm | chmod | chown | chgrp | chflags)
      if any_protected "${args[@]}"; then deny_name "$hit"; fi ;;
    tee)
      if any_protected "${args[@]}"; then deny_name "$hit"; fi ;;
    cp | install | ln | rsync | ditto | gcp | ginstall)
      # Only the destination matters: reading a protected file to copy it elsewhere is fine.
      for a in "${args[@]}"; do
        if [ "$skip_next" -eq 1 ]; then
          skip_next=0
          if is_protected "$a"; then deny_name "$hit"; fi
          continue
        fi
        case "$a" in
          -t | --target-directory) skip_next=1 ;;
          --target-directory=*) if is_protected "${a#*=}"; then deny_name "$hit"; fi ;;
          -*) ;;
          *) last=$a ;;
        esac
      done
      if [ -n "$last" ] && is_protected "$last"; then deny_name "$hit"; fi ;;
    dd)
      for a in "${args[@]}"; do
        case "$a" in of=*) if is_protected "${a#of=}"; then deny_name "$hit"; fi ;; esac
      done ;;
    sed | gsed | perl | ruby)
      for a in "${args[@]}"; do
        case "$a" in
          --in-place* | -[a-z]*i* | -i*)
            case "$a" in --*) case "$a" in --in-place*) ;; *) continue ;; esac ;; esac
            if any_protected "${args[@]}"; then deny_name "$hit"; fi ;;
        esac
      done ;;
    find)
      for a in "${args[@]}"; do
        case "$a" in
          -delete | -exec | -execdir | -ok | -okdir)
            if any_protected "${args[@]}"; then deny_name "$hit"; fi ;;
        esac
      done ;;
    git)
      local j=0 sub=""
      while [ "$j" -lt "${#args[@]}" ]; do
        case "${args[$j]}" in
          -c | -C | --git-dir | --work-tree | --namespace) j=$((j + 2)) ;;
          -*) j=$((j + 1)) ;;
          *) sub=${args[$j]}; break ;;
        esac
      done
      case "$sub" in
        rm | mv | checkout | restore)
          if any_protected "${args[@]:$((j + 1))}"; then deny_name "$hit"; fi ;;
      esac ;;
  esac
  return 0
}

while IFS= read -r seg; do
  read -r -a words <<< "$seg"
  [ "${#words[@]}" -gt 0 ] || continue
  check_command "${words[@]}"
done <<< "$segments"

exit 0
