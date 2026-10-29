#!/usr/bin/env bash
# install-harness.sh — install or update the Decodex harness from GitHub, without the plugin.
#
# The harness lives in a public GitHub repo (delivery-system-starter), pinned to a release tag.
# This script copies ONLY the harness/tooling layer into a project. It never touches the user's
# brand data or generated work (foundations/, frameworks/, library/, content/, engine/,
# references/ contents, or .decodex-sync.json).
#
# Usage:
#   install-harness.sh --mode install --dir <new-or-empty-dir> [--version vX.Y.Z] [--dry-run]
#   install-harness.sh --mode update  --dir <existing-project> [--version vX.Y.Z] [--dry-run] [--force]
#
# One-liner (no plugin, no auth; public repo):
#   curl -fsSL https://raw.githubusercontent.com/JoseCortezz25/delivery-system-starter/v1.1.0/install-harness.sh \
#     | bash -s -- --mode update --dir .
#
# Options:
#   --mode install|update   install: target must be empty/new. update: refresh harness in place.
#   --dir <path>            target project directory (default: current dir).
#   --version <tag>         release tag to install (default: latest tag on the repo).
#   --repo <owner/name>     source repo (default: JoseCortezz25/delivery-system-starter).
#   --dry-run               print what would change; write nothing.
#   --force                 update even if the git working tree is dirty (not recommended).
#   -h, --help              this help.
#
# Run it yourself (not through the AI): the harness guard blocks AI writes to .claude/, CLAUDE.md
# and RULES.md, so updates are a user action.
set -euo pipefail

REPO="JoseCortezz25/delivery-system-starter"
MODE="" TARGET="." VERSION="" DRY=0 FORCE=0
LOCK="codex-lock.json"

# Harness overlay: overwritten wholesale on update (these are the tooling layer, not user data).
HARNESS_PATHS=(".claude" "CLAUDE.md" "RULES.md" ".mcp.json" ".gitignore")
# Folder skeleton: created if missing, NEVER emptied — this is where the user's brand data lives.
SKELETON_DIRS=("foundations" "frameworks" "library" "content" "engine" "references")

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
act() { if [[ $DRY -eq 1 ]]; then printf '[dry-run] %s\n' "$*"; else printf '%s\n' "$*"; fi; }

usage() { sed -n '3,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)    MODE="${2-}"; shift 2 ;;
    --dir)     TARGET="${2-}"; shift 2 ;;
    --version) VERSION="${2-}"; shift 2 ;;
    --repo)    REPO="${2-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --force)   FORCE=1; shift ;;
    -h|--help) usage 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

[[ "$MODE" == "install" || "$MODE" == "update" ]] || die "--mode must be 'install' or 'update'"
for bin in curl tar; do command -v "$bin" >/dev/null 2>&1 || die "'$bin' is required"; done
HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1

# --- Resolve version (latest tag if not given) -------------------------------
if [[ -z "$VERSION" ]]; then
  say "Resolving latest release tag of $REPO ..."
  tags_json="$(curl -fsSL "https://api.github.com/repos/$REPO/tags" || die "cannot reach GitHub for $REPO")"
  if [[ $HAVE_JQ -eq 1 ]]; then
    VERSION="$(printf '%s' "$tags_json" | jq -r '.[].name' | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1)"
  else
    VERSION="$(printf '%s' "$tags_json" | grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)"$/\1/' | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1)"
  fi
  [[ -n "$VERSION" ]] || die "no release tag found on $REPO; pass --version"
fi
say "Using $REPO@$VERSION"

# --- Target checks -----------------------------------------------------------
if [[ "$MODE" == "install" ]]; then
  if [[ -e "$TARGET" && -n "$(ls -A "$TARGET" 2>/dev/null || true)" ]]; then
    die "install target is not empty: $TARGET (use --mode update to refresh in place)"
  fi
  mkdir -p "$TARGET"
else
  [[ -d "$TARGET" ]] || die "update target does not exist: $TARGET"
  if [[ ! -d "$TARGET/.claude" && ! -f "$TARGET/$LOCK" ]]; then
    die "no harness found in $TARGET (no .claude/ or $LOCK). Use --mode install for a fresh project."
  fi
  if [[ $FORCE -eq 0 ]] && git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    [[ -z "$(git -C "$TARGET" status --porcelain)" ]] || \
      die "git working tree in $TARGET is dirty. Commit/stash first, or pass --force."
  fi
fi
TARGET_ABS="$(cd "$TARGET" && pwd -P)"

# --- Download + extract to a temp staging dir --------------------------------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
say "Downloading tarball ..."
curl -fsSL "https://github.com/$REPO/archive/refs/tags/$VERSION.tar.gz" \
  | tar xz -C "$TMP" --strip-components=1 || die "download/extract failed for $REPO@$VERSION"

# --- Copy the harness overlay ------------------------------------------------
say ""; say "Applying harness ($MODE) to $TARGET_ABS:"
for p in "${HARNESS_PATHS[@]}"; do
  src="$TMP/$p"; dst="$TARGET_ABS/$p"
  [[ -e "$src" ]] || { say "  skip (not in release): $p"; continue; }
  act "  overwrite $p"
  if [[ $DRY -eq 0 ]]; then
    if [[ -d "$src" ]]; then rm -rf "$dst"; fi   # dir: replace wholesale so removed files are dropped
    mkdir -p "$(dirname "$dst")"
    cp -R "$src" "$dst"
  fi
done

# --- Ensure the folder skeleton (never clobber existing data) ----------------
for d in "${SKELETON_DIRS[@]}"; do
  dst="$TARGET_ABS/$d"
  if [[ -d "$dst" ]]; then
    say "  keep (has your data): $d/"
  else
    act "  create $d/ (+ .gitkeep)"
    if [[ $DRY -eq 0 ]]; then mkdir -p "$dst"; : > "$dst/.gitkeep"; fi
  fi
done

# --- Record the installed version --------------------------------------------
if [[ $DRY -eq 0 ]]; then
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ $HAVE_JQ -eq 1 && -f "$TARGET_ABS/$LOCK" ]]; then
    tmp_lock="$(mktemp)"
    jq --arg v "$VERSION" --arg r "$REPO" --arg t "$now" \
       '.harnessVersion=$v | .harnessRepo=$r | .harnessUpdatedAt=$t' \
       "$TARGET_ABS/$LOCK" > "$tmp_lock" && mv "$tmp_lock" "$TARGET_ABS/$LOCK"
  else
    cat > "$TARGET_ABS/$LOCK" <<JSON
{
  "harnessRepo": "$REPO",
  "harnessVersion": "$VERSION",
  "harnessUpdatedAt": "$now"
}
JSON
  fi
  act "  wrote $LOCK (version $VERSION)"
fi

say ""
if [[ $DRY -eq 1 ]]; then
  say "Dry run only — nothing was written."
else
  say "Done. Harness $VERSION applied to $TARGET_ABS."
  say "Review with: git -C \"$TARGET_ABS\" status  &&  git -C \"$TARGET_ABS\" diff"
fi
