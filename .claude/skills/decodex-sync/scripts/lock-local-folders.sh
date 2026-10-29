#!/usr/bin/env bash
# Locks the local brand folders after a fully successful decodex-sync.
#
# Usage: bash .claude/skills/decodex-sync/scripts/lock-local-folders.sh --brand-id <id> --brand-name <name>
#
# Writes the sync marker (.decodex-sync.json) at the project root with the sha256 of every file under
# foundations/ and frameworks/. From then on the protection hooks freeze both folders for the AI.
# It refuses when the marker already exists, and never touches the folders themselves.
# Only the user unlocks the project, by deleting the marker themselves.
# Exit codes: 0 locked, 1 refused or failed, 2 bad usage.
set -euo pipefail

MARKER=".decodex-sync.json"
FOLDERS=(foundations frameworks)

usage() {
  printf 'Usage: %s --brand-id <id> --brand-name <name>\n' "$0" >&2
  exit 2
}

fail() {
  printf 'NOT LOCKED: %s\n' "$1" >&2
  exit 1
}

brand_id=""
brand_name=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --brand-id) [ "$#" -ge 2 ] || usage; brand_id=$2; shift 2 ;;
    --brand-id=*) brand_id=${1#*=}; shift ;;
    --brand-name) [ "$#" -ge 2 ] || usage; brand_name=$2; shift 2 ;;
    --brand-name=*) brand_name=${1#*=}; shift ;;
    -h | --help) usage ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage ;;
  esac
done
[ -n "$brand_id" ] && [ -n "$brand_name" ] || usage

command -v jq >/dev/null 2>&1 || fail "jq is not installed (for example: brew install jq)."

# The project root: CLAUDE_PROJECT_DIR, or four levels above this script
# (<project>/.claude/skills/decodex-sync/scripts/).
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  proj=$CLAUDE_PROJECT_DIR
else
  proj=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd -P)
fi
cd -- "$proj" || fail "the project folder $proj cannot be opened."

if [ -e "$MARKER" ] || [ -L "$MARKER" ]; then
  fail "$MARKER already exists, so this project is already locked. Only the user can unlock it, by deleting that file themselves."
fi
for d in "${FOLDERS[@]}"; do
  [ -d "$d" ] && [ ! -L "$d" ] || fail "$d/ is missing or is not a real folder."
done

sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | cut -d' ' -f1
  else
    shasum -a 256 -- "$1" | cut -d' ' -f1
  fi
}

# Every regular file under both folders, in a stable order. A symlink or other special file is
# refused: the lock records file contents, and a link could point anywhere.
special=$(find "${FOLDERS[@]}" ! -type f ! -type d -print 2>/dev/null | head -n 5 || true)
[ -z "$special" ] || fail "these entries are not regular files or folders: $(printf '%s' "$special" | paste -sd ',' -)."

files_json="[]"
count=0
while IFS= read -r -d '' f; do
  h=$(sha "$f") || fail "$f could not be read."
  [ -n "$h" ] || fail "$f could not be read."
  files_json=$(jq -c --arg p "$f" --arg h "$h" '. + [{path: $p, sha256: $h}]' <<< "$files_json") \
    || fail "the file list could not be built."
  count=$((count + 1))
done < <(find "${FOLDERS[@]}" -type f -print0 | LC_ALL=C sort -z)

synced_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
tmp="$MARKER.tmp.$$"
trap 'rm -f -- "$tmp"' EXIT

jq -n \
  --arg syncedAt "$synced_at" \
  --arg brandId "$brand_id" \
  --arg brandName "$brand_name" \
  --argjson files "$files_json" \
  '{schemaVersion: 1, syncedAt: $syncedAt, brandId: $brandId, brandName: $brandName,
    folders: ["foundations", "frameworks"], files: $files}' > "$tmp" \
  || fail "the marker could not be written."

# ln fails when the marker appeared meanwhile, so an existing marker is never overwritten.
ln -- "$tmp" "$MARKER" 2>/dev/null || fail "$MARKER could not be created (it may have appeared meanwhile)."
rm -f -- "$tmp"
trap - EXIT

jq empty "$MARKER" 2>/dev/null || fail "$MARKER was written but is not valid JSON; ask the user to check it."

printf 'LOCKED: foundations/ and frameworks/ (%d files) for brand "%s" (%s) at %s.\n' \
  "$count" "$brand_name" "$brand_id" "$synced_at"
printf 'Marker: %s/%s\n' "$proj" "$MARKER"
