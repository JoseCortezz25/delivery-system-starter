#!/usr/bin/env bash
# PreToolUse (Bash): best-effort first barrier against shell commands that modify the protected
# harness files (GUARD_PROTECTED in guard-lib.sh: CLAUDE.md, RULES.md, .mcp.json, .gitignore,
# codex-lock.json, .decodex-sync.json and .claude/).
# It only gives an early, readable denial for the obvious cases. The real control is the integrity
# guard (guard-snapshot.sh + guard-verify.sh), which restores anything a command changed anyway.
#
# Frozen brand folders: once the decodex-sync skill wrote the sync marker (.decodex-sync.json), it
# also denies shell commands that touch foundations/ or frameworks/ in any way, READING included:
# any command naming them (except echo/printf and git add/commit/status), interpreter one-liners and
# xargs pipelines whose text names them, and recursive searches, copies or archives whose scope is
# the project root or a folder above it. The READ block is BEST-EFFORT ONLY: a shell can always
# reach a file without naming it (variables, encoded names, scripts written beforehand), and these
# folders are not in the integrity snapshot. Its job is to keep an honest AI on the documented path
# (Decodex is the source of truth), not to stop a determined bypass. Nothing here applies while the
# marker is absent.
# Written for bash 3.2 (macOS default): no ${var,,}, no associative arrays, no mapfile.

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

input=$(cat 2>/dev/null)

# shellcheck source=/dev/null
. "$(dirname -- "${BASH_SOURCE[0]}")/guard-lib.sh" 2>/dev/null && [ -n "${GUARD_PROTECTED:-}" ] \
  || deny "The list of protected project files could not be loaded, so shell commands cannot be checked. Ask the user to check .claude/hooks/. See RULES.md."

if ! command -v jq >/dev/null 2>&1; then
  deny "jq is not installed, so shell commands cannot be checked against the protected project files. Install jq (for example: brew install jq) and try again. See RULES.md."
fi

command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) \
  || deny "The shell command could not be read to check it against the protected project files. See RULES.md."
[ -n "$command" ] || exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Names are matched case-insensitively (macOS file systems are case-insensitive by default).
lc=$(lower "$command")
proj_lc=$(lower "$GUARD_PROJ")
prot_lc=$(lower "$GUARD_PROTECTED")
root_lc=$(lower "$(cd -- "$GUARD_PROJ" 2>/dev/null && pwd -P || printf '%s' "$GUARD_PROJ")")

locked=0
if [ -e "$GUARD_PROJ/$GUARD_SYNC_MARKER" ] || [ -L "$GUARD_PROJ/$GUARD_SYNC_MARKER" ]; then locked=1; fi
brand_alt=$(printf '%s' "$GUARD_BRAND_DIRS" | tr ' ' '|')
brand_re="(^|[^a-z0-9_-])($brand_alt)([^a-z0-9_-]|$)"

deny_brand() {
  deny "foundations/ and frameworks/ are frozen: this project was synced to Decodex (.decodex-sync.json), so the AI may not read, search, copy or change them, not even through the shell. The brand data lives in Decodex: read it with get_foundations, get_brand_colors, get_brand_fonts, get_brand_voice, list_frameworks and get_framework; framework drafts go in drafts/. Scope searches, copies and archives to specific folders that are not frozen (for example engine/, content/, library/, references/ or drafts/), never the project root. Do not try to work around this block. See RULES.md."
}

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

# names_match NAMES WORD: true when WORD names a path in the space-separated NAMES (any path
# component equal to a name), or is a glob at the project root that could expand to one (codex-lo*,
# CLAUDE*, .cla*, *). Sets $hit to the matched name.
hit=""
names_match() {
  local w=$2 comp acc="" rootish dots=1 name i
  local -a names
  read -r -a names <<< "$1"
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
    for name in "${names[@]}"; do
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

# is_protected WORD: WORD names a protected harness path (GUARD_PROTECTED).
is_protected() { names_match "$prot_lc" "$1"; }

# is_brand WORD: the project is locked and WORD names a frozen brand folder (git's REV:PATH included).
is_brand() {
  [ "$locked" -eq 1 ] || return 1
  names_match "$GUARD_BRAND_DIRS" "${1//:/\/}"
}

# covers_root WORD: WORD is an existing folder that is the project root or a folder above it, so a
# recursive command run on it reaches the frozen brand folders.
covers_root() {
  local p=$1 d
  p=${p//\"/}
  p=${p//\'/}
  case "$p" in '~') p=$HOME ;; '~/'*) p="$HOME/${p#\~/}" ;; esac
  case "$p" in /*) ;; *) p="$cwd/$p" ;; esac
  [ -d "$p" ] || return 1
  d=$(cd -- "$p" 2>/dev/null && pwd -P) || return 1
  d=$(lower "$d")
  [ "$d" = "/" ] && return 0
  case "$root_lc" in "$d" | "$d/"*) return 0 ;; esac
  return 1
}

# 1) Redirections (>, >>, >|, &>, &>>) into a protected name; when locked, also any redirection (<
#    included) from or into a frozen brand folder.
rest=$lc
re='(&>>|&>|>>|>\||>|<)[[:space:]]*([^[:space:];&|<>()]+)'
while [[ $rest =~ $re ]]; do
  target=${BASH_REMATCH[2]}
  if [ "${BASH_REMATCH[1]}" != "<" ] && is_protected "$target"; then deny_name "$hit"; fi
  if is_brand "$target"; then deny_brand; fi
  rest=${rest#*"${BASH_REMATCH[0]}"}
done

# 1b) Locked: an xargs pipeline that names a frozen folder anywhere (echo foundations/x | xargs cat).
xargs_re='(^|[^a-z0-9_-])xargs([^a-z0-9_-]|$)'
if [ "$locked" -eq 1 ] && [[ $lc =~ $brand_re ]] && [[ $lc =~ $xargs_re ]]; then
  deny_brand
fi

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

git_sub() { # git_sub ARG...: sets $git_cmd to git's subcommand and $git_rest to the index after it
  local j=0 a
  local -a g=("$@")
  git_cmd=""
  git_rest=${#g[@]}
  while [ "$j" -lt "${#g[@]}" ]; do
    a=${g[$j]}
    case "$a" in
      -c | -C | --git-dir | --work-tree | --namespace) j=$((j + 2)) ;;
      -*) j=$((j + 1)) ;;
      *) git_cmd=$a; git_rest=$((j + 1)); return 0 ;;
    esac
  done
}

# path_exists WORD: WORD (quotes removed, ~ expanded) is an existing path, relative to the working folder.
path_exists() {
  local p=$1
  p=${p//\"/}
  p=${p//\'/}
  case "$p" in '~') p=$HOME ;; '~/'*) p="$HOME/${p#\~/}" ;; esac
  case "$p" in /*) ;; *) p="$cwd/$p" ;; esac
  [ -e "$p" ]
}

check_brand() { # check_brand CMD ARG...: locked project only; one simple command, lowercased
  local cmd=$1 sub="" a recursive=0 default_cwd=0 positional=0 skip_first=0 paths_done=0
  shift
  local -a args=("$@") scope=()

  case "$cmd" in
    echo | printf | true | false | :) return 0 ;; # printing a name reads nothing
  esac
  if [ "$cmd" = "git" ]; then
    git_sub "${args[@]}"
    sub=$git_cmd
    case "$sub" in add | commit | status) return 0 ;; esac
  fi

  # Interpreter one-liners and heredocs: the paths sit inside code, so the whole text is checked.
  case "$cmd" in
    python* | node | nodejs | deno | bun | ruby | perl | php | lua | osascript | swift | pwsh \
      | awk | gawk | nawk | mawk | jq | yq | sqlite3 | duckdb)
      if [[ $lc =~ $brand_re ]]; then deny_brand; fi ;;
  esac

  # Any other command naming a frozen folder, whatever it does with it (read, copy, change, list).
  for a in "${args[@]}"; do
    if is_brand "$a"; then deny_brand; fi
  done

  # Recursive commands that read file contents, whose scope (their existing path arguments, or the
  # working folder when they have none) is the project root or above it: they would reach the frozen
  # folders without naming them. Listing names only (ls -R, tree, du) is not blocked.
  case "$cmd" in
    rg | ag | ack | fd | fdfind) recursive=1; default_cwd=1; skip_first=1 ;;
    grep | egrep | fgrep | ggrep)
      for a in "${args[@]}"; do
        case "$a" in --recursive | --dereference-recursive) recursive=1 ;; --*) ;; -*r*) recursive=1 ;; esac
      done
      default_cwd=1; skip_first=1 ;;
    find | gfind) recursive=1; default_cwd=1 ;;
    tar | gtar | bsdtar | zip | 7z | 7za | cp | gcp | rsync | ditto | scp) recursive=1 ;;
    git)
      case "$sub" in
        archive | bundle) deny_brand ;; # they package the whole tracked tree
        grep) recursive=1; default_cwd=1; skip_first=1 ;;
      esac ;;
  esac
  [ "$recursive" -eq 1 ] || return 0
  for a in "${args[@]}"; do # an explicit pattern option means every positional is a path
    case "$a" in -e | --regexp | --regexp=* | -f | --file | --file=*) skip_first=0 ;; esac
  done
  [ "$cmd" = "git" ] && args=("${args[@]:$git_rest}")
  for a in "${args[@]}"; do
    case "$a" in
      -* | '!' | '(')
        # find takes its paths before the first option or expression.
        case "$cmd" in find | gfind) paths_done=1 ;; esac
        continue ;;
    esac
    [ "$paths_done" -eq 1 ] && continue
    positional=$((positional + 1))
    if [ "$skip_first" -eq 1 ] && [ "$positional" -eq 1 ]; then continue; fi
    if path_exists "$a"; then scope+=("$a"); fi
  done
  if [ "${#scope[@]}" -eq 0 ] && [ "$default_cwd" -eq 1 ]; then scope=("."); fi
  for a in "${scope[@]}"; do
    if covers_root "$a"; then deny_brand; fi
  done
  return 0
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
  if is_brand "$cmd"; then deny_brand; fi # running or sourcing a file inside a frozen folder
  cmd=${cmd##*/}
  local -a args=("${w[@]:$((i + 1))}")
  if [ "$locked" -eq 1 ]; then check_brand "$cmd" "${args[@]}"; fi
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
