#!/usr/bin/env bash
# Shared helpers for the harness integrity guard (sourced by guard-snapshot.sh and guard-verify.sh).
# The guard snapshots the protected set before every shell command and restores it afterwards if the
# command changed it. It does not use git, so it also works in projects that are not repositories.
# It is also the single source of the protected names for protect-claude-dir.sh,
# block-protected-delete.sh and protect-local-brand.sh, which source it and fail closed without it.

GUARD_PROJ=${CLAUDE_PROJECT_DIR:-$PWD}

# The sync marker written by the decodex-sync skill once foundations/ and frameworks/ were synced to
# Decodex. It is protected ADD-ONLY: once it exists the AI can never edit or delete it (the hooks deny
# it and the guard restores it), but creating it while it is absent is accepted, because creating it
# only adds restrictions. Only the user unlocks the project, by deleting it themselves.
GUARD_SYNC_MARKER=".decodex-sync.json"
GUARD_PROTECTED="CLAUDE.md RULES.md .mcp.json .gitignore codex-lock.json .claude $GUARD_SYNC_MARKER"
# Local brand folders frozen while the sync marker exists (see protect-local-brand.sh). They are not
# part of the snapshot: the PreToolUse hooks are their barrier.
GUARD_BRAND_DIRS="foundations frameworks"

guard_sha() { # guard_sha FILE...: "<sha256>  <path>" per file
  if command -v sha256sum >/dev/null 2>&1; then sha256sum -- "$@"; else shasum -a 256 -- "$@"; fi
}

if [ -d "$GUARD_PROJ/.git" ]; then
  GUARD_STATE="$GUARD_PROJ/.git/decodex-guard"
else
  GUARD_STATE="${TMPDIR:-/tmp}"
  GUARD_STATE="${GUARD_STATE%/}/decodex-guard-$(printf '%s' "$GUARD_PROJ" | guard_sha /dev/stdin 2>/dev/null | cut -c1-16)"
fi

# guard_paths: sets GUARD_PATHS to the protected paths that currently exist.
guard_paths() {
  local n
  GUARD_PATHS=()
  for n in $GUARD_PROTECTED; do
    if [ -e "$GUARD_PROJ/$n" ] || [ -L "$GUARD_PROJ/$n" ]; then GUARD_PATHS+=("$n"); fi
  done
}

# guard_manifest: prints one line per fact about the protected set, sorted:
#   T <d|f|l> <path>   type        M <mode> <path>   permissions
#   H <sha256> <path>  file content L <sha256> <path> symlink target
guard_manifest() {
  (
    cd "$GUARD_PROJ" || exit 1
    guard_paths
    [ "${#GUARD_PATHS[@]}" -gt 0 ] || exit 0
    files=()
    all=()
    while IFS= read -r -d '' f; do
      all+=("$f")
      if [ -L "$f" ]; then
        printf 'T l %s\n' "$f"
        t=$(readlink -- "$f" | guard_sha /dev/stdin | cut -d' ' -f1) || exit 1
        printf 'L %s %s\n' "$t" "$f"
      elif [ -d "$f" ]; then
        printf 'T d %s\n' "$f"
      else
        printf 'T f %s\n' "$f"
        files+=("$f")
      fi
    done < <(find "${GUARD_PATHS[@]}" -print0)
    # An unreadable file simply gets no H line, so it shows up as a change (and gets restored).
    if [ "${#files[@]}" -gt 0 ]; then
      guard_sha "${files[@]}" 2>/dev/null | while read -r h p; do printf 'H %s %s\n' "$h" "$p"; done
    fi
    if stat -c '%a' / >/dev/null 2>&1; then
      stat -c 'M %a %n' -- "${all[@]}" 2>/dev/null
    else
      stat -f 'M %Lp %N' -- "${all[@]}" 2>/dev/null
    fi
    exit 0
  ) | LC_ALL=C sort
  return "${PIPESTATUS[0]}"
}

# guard_check_and_restore: compares the protected set with the snapshot. Returns 1 when nothing
# changed; otherwise restores the snapshot exactly, sets GUARD_CHANGED (", "-separated paths) and
# returns 0 when the restore succeeded or 2 when it did not.
# guard_drop_new_marker OLD CUR: prints CUR without the sync marker's lines when OLD (the snapshot)
# has no marker, so creating the marker is never seen as a change. Once the snapshot holds the
# marker, any change to it (edit, delete, mode) is a change like any other and gets restored.
guard_drop_new_marker() {
  if printf '%s\n' "$1" | LC_ALL=C awk -v m="$GUARD_SYNC_MARKER" '$3 == m { f = 1 } END { exit !f }'; then
    printf '%s\n' "$2"
  else
    printf '%s\n' "$2" | LC_ALL=C awk -v m="$GUARD_SYNC_MARKER" '$3 != m'
  fi
}

guard_check_and_restore() {
  local cur old changed n list count
  cur=$(guard_manifest) || return 2
  old=$(<"$GUARD_STATE/manifest") || return 2
  cur=$(guard_drop_new_marker "$old" "$cur")
  [ "$cur" = "$old" ] && return 1

  changed=$(comm -3 <(printf '%s\n' "$old") <(printf '%s\n' "$cur") \
    | sed -E 's/^[[:space:]]+//' | cut -d' ' -f3- | LC_ALL=C sort -u)

  # Remove every protected root path touched by the change, then extract the snapshot over the
  # project: this also deletes new files under .claude/ and protected files that did not exist.
  for n in $GUARD_PROTECTED; do
    if printf '%s\n' "$changed" | LC_ALL=C awk -v n="$n" '$0 == n || index($0, n "/") == 1 { f = 1 } END { exit !f }'; then
      chmod -R u+rwX -- "${GUARD_PROJ:?}/$n" 2>/dev/null
      rm -rf -- "${GUARD_PROJ:?}/$n"
    fi
  done
  tar -xpf "$GUARD_STATE/snap.tar" -C "$GUARD_PROJ" 2>/dev/null

  count=$(printf '%s\n' "$changed" | wc -l | tr -d ' ')
  list=$(printf '%s\n' "$changed" | head -n 10 | paste -sd ',' - | sed 's/,/, /g')
  [ "$count" -gt 10 ] && list="$list and $((count - 10)) more"
  GUARD_CHANGED=$list

  cur=$(guard_manifest) || return 2
  cur=$(guard_drop_new_marker "$old" "$cur")
  [ "$cur" = "$old" ] || return 2
  return 0
}

guard_json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n\t' '  '
}
