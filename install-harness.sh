#!/usr/bin/env bash
# install-harness.sh — install or update the Decodex harness from GitHub, without the plugin.
#
# The harness lives in a public GitHub repo (delivery-system-starter), pinned to a release tag.
# This script copies ONLY the harness/tooling layer into a project. It never touches the user's
# brand data or generated work (foundations/, frameworks/, library/ or resources/, content/,
# engine/, references/ contents, or .decodex-sync.json).
#
# Usage:
#   install-harness.sh --mode install --dir <new-or-empty-dir> [--version vX.Y.Z] [--dry-run]
#   install-harness.sh --mode update  --dir <existing-project> [--version vX.Y.Z] [--dry-run] [--force]
#
# One-liner (no plugin, no auth; public repo). The script is attached to every release as an asset:
#   curl -fsSL https://github.com/JoseCortezz25/delivery-system-starter/releases/latest/download/install-harness.sh \
#     | bash -s -- --mode update --dir .
#
# Options:
#   --mode install|update   install: target must be empty/new. update: refresh harness in place.
#   --dir <path>            target project directory (default: current dir).
#   --version <tag>         release tag to install (default: latest tag on the repo).
#   --repo <owner/name>     source repo (default: JoseCortezz25/delivery-system-starter).
#   --dry-run               print what would change; write nothing.
#   --force                 update even if harness files have uncommitted changes (they are replaced).
#   --source-dir <path>     use a local copy of the harness instead of downloading (for testing).
#   -h, --help              this help.
#
# Update keeps the user's data: codex-lock.json (brand, project) is merged, not rewritten;
# .mcp.json keeps any extra MCP servers; .gitignore keeps the user's own lines;
# .claude/settings.local.json is preserved. Uncommitted work in content/, library/, resources/, etc. is fine.
# The brand assets folder is library/ (newer projects) or resources/ (older ones): both are valid and
# update never renames, moves or merges them, and never creates an empty library/ beside resources/.
# Legacy v1.1.0 projects are migrated: an empty knowledge/ is removed, and retired harness files go
# to .harness-backup/<timestamp>/.
# JSON merges use jq, or python3 if jq is missing; with neither, JSON files are left untouched.
#
# Run it yourself (not through the AI): the harness guard blocks AI writes to .claude/, CLAUDE.md
# and RULES.md, so updates are a user action.
set -euo pipefail

REPO="JoseCortezz25/delivery-system-starter"
MODE="" TARGET="." VERSION="" DRY=0 FORCE=0 SOURCE_DIR=""
LOCK="codex-lock.json"

# Harness overlay: overwritten wholesale on update (these are the tooling layer, not user data).
HARNESS_PATHS=(".claude" "CLAUDE.md" "RULES.md" ".mcp.json" ".gitignore")
# Folder skeleton: created if missing, NEVER emptied — this is where the user's brand data lives.
SKELETON_DIRS=("foundations" "frameworks" "library" "content" "engine" "references")
# Files older harness releases shipped and no longer do (v1.1.0 "Codex" layout). On update they are
# moved to a backup folder, never deleted.
RETIRED_FILES=("AGENTS.md" "codex-flow.svg")
# MCP servers older releases shipped and no longer do; removed from .mcp.json on update.
RETIRED_MCP_SERVERS=("figma-desktop")

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
act() { if [[ $DRY -eq 1 ]]; then printf '[dry-run] %s\n' "$*"; else printf '%s\n' "$*"; fi; }

usage() { sed -n '3,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)    MODE="${2-}"; shift 2 ;;
    --dir)     TARGET="${2-}"; shift 2 ;;
    --version) VERSION="${2-}"; shift 2 ;;
    --repo)    REPO="${2-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --force)   FORCE=1; shift ;;
    --source-dir) SOURCE_DIR="${2-}"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

[[ "$MODE" == "install" || "$MODE" == "update" ]] || die "--mode must be 'install' or 'update'"
for bin in curl tar find; do command -v "$bin" >/dev/null 2>&1 || die "'$bin' is required"; done
HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1
# JSON tool for merges: jq preferred, python3 as fallback, "none" means never rewrite existing JSON.
JSON_TOOL="none"
if [[ $HAVE_JQ -eq 1 ]]; then JSON_TOOL="jq"
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null 2>&1; then JSON_TOOL="python3"; fi

# --- Resolve version (latest tag if not given) -------------------------------
if [[ -n "$SOURCE_DIR" ]]; then
  [[ -d "$SOURCE_DIR" ]] || die "--source-dir does not exist: $SOURCE_DIR"
  [[ -n "$VERSION" ]] || VERSION="local"
elif [[ -z "$VERSION" ]]; then
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
  # Only uncommitted changes in files this script replaces block the update; brand work
  # (content/, library/, resources/, foundations/ ...) is never touched, so it may be dirty.
  if [[ $FORCE -eq 0 ]] && git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    dirty="$(cd "$TARGET" && git status --porcelain -- "${HARNESS_PATHS[@]}" 2>/dev/null | grep -v ' \.claude/settings\.local\.json$' || true)"
    [[ -z "$dirty" ]] || \
      die "harness files in $TARGET have uncommitted changes (they would be replaced):
$dirty
Commit/stash them first, or pass --force."
  fi
fi
TARGET_ABS="$(cd "$TARGET" && pwd -P)"

# --- Download + extract to a temp staging dir --------------------------------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
COMMIT=""
if [[ -n "$SOURCE_DIR" ]]; then
  say "Using local source $SOURCE_DIR ..."
  (cd "$SOURCE_DIR" && tar cf - --exclude .git .) | tar xf - -C "$TMP" || die "cannot copy $SOURCE_DIR"
  COMMIT="$(git -C "$SOURCE_DIR" rev-parse HEAD 2>/dev/null || true)"
else
  say "Downloading tarball ..."
  curl -fsSL "https://github.com/$REPO/archive/refs/tags/$VERSION.tar.gz" \
    | tar xz -C "$TMP/" --strip-components=1 || die "download/extract failed for $REPO@$VERSION"
  # Exact commit of the tag (plain-text API response; empty if unavailable).
  COMMIT="$(curl -fsSL -H 'Accept: application/vnd.github.sha' \
    "https://api.github.com/repos/$REPO/commits/$VERSION" 2>/dev/null || true)"
  [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || COMMIT=""
fi

# --- JSON helpers (jq or python3) --------------------------------------------
RETIRED_JSON="[$(printf '"%s",' "${RETIRED_MCP_SERVERS[@]}" | sed 's/,$//')]"
# merge_mcp <user .mcp.json> <release .mcp.json> <out>: user file with release servers on top.
merge_mcp() {
  case "$JSON_TOOL" in
    jq) jq -s --argjson retired "$RETIRED_JSON" \
          '.[0] * {mcpServers: ((.[0].mcpServers // {}) + (.[1].mcpServers // {}))}
           | .mcpServers |= with_entries(select(.key as $k | ($retired | index($k)) | not))' \
          "$1" "$2" > "$3" ;;
    python3) python3 - "$1" "$2" "$3" "$RETIRED_JSON" <<'PYEOF'
import json, sys
user, rel, out, retired = sys.argv[1:5]
u = json.load(open(user)); r = json.load(open(rel))
u.setdefault("mcpServers", {}).update(r.get("mcpServers", {}))
for name in json.loads(retired): u["mcpServers"].pop(name, None)
json.dump(u, open(out, "w"), indent=2); open(out, "a").write("\n")
PYEOF
    ;;
    *) return 1 ;;
  esac
}

# update_lock <lock> <out>: set harness.{name,version,repo,commit,updatedAt}, keep every other key,
# and drop the legacy flat keys (harnessVersion/harnessRepo/harnessUpdatedAt).
update_lock() {
  local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  case "$JSON_TOOL" in
    jq) jq --arg v "$VERSION" --arg r "https://github.com/$REPO" --arg c "$COMMIT" --arg t "$now" '
          (.schemaVersion //= 1)
          | .harness = ((.harness // {}) + {name: "decodex", version: $v, repo: $r, updatedAt: $t})
          | (if $c == "" then del(.harness.commit) else .harness.commit = $c end)
          | del(.harnessVersion, .harnessRepo, .harnessUpdatedAt)' "$1" > "$2" ;;
    python3) python3 - "$1" "$2" "$VERSION" "https://github.com/$REPO" "$COMMIT" "$now" <<'PYEOF'
import json, sys
src, out, v, r, c, t = sys.argv[1:7]
d = json.load(open(src))
d.setdefault("schemaVersion", 1)
h = d.get("harness") if isinstance(d.get("harness"), dict) else {}
h.update({"name": "decodex", "version": v, "repo": r, "updatedAt": t})
if c: h["commit"] = c
else: h.pop("commit", None)
d["harness"] = h
for k in ("harnessVersion", "harnessRepo", "harnessUpdatedAt"): d.pop(k, None)
json.dump(d, open(out, "w"), indent=2); open(out, "a").write("\n")
PYEOF
    ;;
    *) return 1 ;;
  esac
}

# --- Copy the harness overlay ------------------------------------------------
say ""; say "Applying harness ($MODE) to $TARGET_ABS:"
for p in "${HARNESS_PATHS[@]}"; do
  src="$TMP/$p"; dst="$TARGET_ABS/$p"
  [[ -e "$src" ]] || { say "  skip (not in release): $p"; continue; }

  # .mcp.json: keep the user's extra servers, refresh the harness ones.
  if [[ "$p" == ".mcp.json" && -f "$dst" ]]; then
    if [[ "$JSON_TOOL" == "none" ]]; then
      say "  keep $p (no jq/python3 to merge it safely; compare with the release by hand)"
    else
      act "  merge $p (your extra MCP servers are kept)"
      if [[ $DRY -eq 0 ]]; then
        merge_mcp "$dst" "$src" "$TMP/mcp.merged" || die "cannot merge $p (invalid JSON?)"
        mv "$TMP/mcp.merged" "$dst"
      fi
    fi
    continue
  fi

  # .gitignore: append the release lines that are missing; never drop the user's lines.
  if [[ "$p" == ".gitignore" && -f "$dst" ]]; then
    missing="$(grep -vxF -f "$dst" "$src" | grep -v '^[[:space:]]*$' || true)"
    if [[ -z "$missing" ]]; then
      say "  keep $p (already up to date)"
    else
      act "  add missing lines to $p"
      if [[ $DRY -eq 0 ]]; then
        [[ -z "$(tail -c1 "$dst")" ]] || printf '\n' >> "$dst"
        printf '\n# Added by Decodex harness %s\n%s\n' "$VERSION" "$missing" >> "$dst"
      fi
    fi
    continue
  fi

  act "  overwrite $p"
  if [[ $DRY -eq 0 ]]; then
    if [[ "$p" == ".claude" && -f "$dst/settings.local.json" ]]; then
      cp "$dst/settings.local.json" "$TMP/settings.local.json.keep"   # personal settings survive
    fi
    if [[ -d "$src" ]]; then rm -rf "$dst"; fi   # dir: replace wholesale so removed files are dropped
    mkdir -p "$(dirname "$dst")"
    cp -R "$src" "$dst"
    if [[ -f "$TMP/settings.local.json.keep" && "$p" == ".claude" ]]; then
      mv "$TMP/settings.local.json.keep" "$dst/settings.local.json"
      say "  keep .claude/settings.local.json (your personal settings)"
    fi
  fi
done

# --- Migrate the legacy v1.1.0 layout (update only; never deletes user data) -----
# only_gitkeep <dir>: true when the dir holds no files other than .gitkeep placeholders.
# Fails safe: if find errors, the dir is treated as having data and is never removed.
only_gitkeep() { local out; out="$(find "$1" -type f ! -name .gitkeep -print -quit 2>/dev/null)" || return 1; [[ -z "$out" ]]; }
if [[ "$MODE" == "update" ]]; then
  BACKUP="$TARGET_ABS/.harness-backup/$(date -u +%Y%m%dT%H%M%SZ)"
  for f in "${RETIRED_FILES[@]}"; do
    [[ -e "$TARGET_ABS/$f" ]] || continue
    act "  move old harness file $f to ${BACKUP#"$TARGET_ABS"/}/"
    if [[ $DRY -eq 0 ]]; then mkdir -p "$BACKUP"; mv "$TARGET_ABS/$f" "$BACKUP/"; fi
  done
  # resources/ (older projects) is a valid brand assets folder: kept as it is, never moved.
  if [[ -d "$TARGET_ABS/resources" ]]; then
    say "  keep resources/ (brand assets folder, not renamed or moved)"
  fi
  # knowledge/ moved to Decodex; an empty one is removed, one with files is kept.
  if [[ -d "$TARGET_ABS/knowledge" ]]; then
    if only_gitkeep "$TARGET_ABS/knowledge"; then
      act "  remove empty knowledge/ (brand knowledge now lives in Decodex)"
      [[ $DRY -eq 1 ]] || rm -rf "$TARGET_ABS/knowledge"
    else
      say "  keep knowledge/ (it has your files; save them to the brand in Decodex, then delete it)"
    fi
  fi
fi

# --- Ensure the folder skeleton (never clobber existing data) ----------------
for d in "${SKELETON_DIRS[@]}"; do
  dst="$TARGET_ABS/$d"
  if [[ "$d" == "library" && ! -d "$dst" && -d "$TARGET_ABS/resources" ]]; then
    say "  skip library/ (this project uses resources/ as its brand assets folder)"
  elif [[ -d "$dst" ]]; then
    say "  keep (has your data): $d/"
  else
    act "  create $d/ (+ .gitkeep)"
    if [[ $DRY -eq 0 ]]; then mkdir -p "$dst"; : > "$dst/.gitkeep"; fi
  fi
done

# --- Record the installed version --------------------------------------------
# Format matches the plugin: harness.version (nested). Brand/project keys are always kept.
if [[ -f "$TARGET_ABS/$LOCK" && "$JSON_TOOL" == "none" ]]; then
  say "  keep $LOCK unchanged (no jq/python3; version not recorded, your brand data is safe)"
else
  act "  record version $VERSION in $LOCK"
  if [[ $DRY -eq 0 ]]; then
    lock_in="$TARGET_ABS/$LOCK"
    if [[ ! -f "$lock_in" ]]; then lock_in="$TMP/empty-lock.json"; printf '{}
' > "$lock_in"; fi
    if [[ "$JSON_TOOL" == "none" ]]; then
      cat > "$TARGET_ABS/$LOCK" <<JSON
{
  "schemaVersion": 1,
  "harness": {
    "name": "decodex",
    "version": "$VERSION",
    "repo": "https://github.com/$REPO"
  }
}
JSON
    else
      update_lock "$lock_in" "$TMP/lock.new" || die "cannot update $LOCK (invalid JSON?)"
      mv "$TMP/lock.new" "$TARGET_ABS/$LOCK"
    fi
  fi
fi

say ""
if [[ $DRY -eq 1 ]]; then
  say "Dry run only — nothing was written."
else
  say "Done. Harness $VERSION applied to $TARGET_ABS."
  say "Review with: git -C \"$TARGET_ABS\" status  &&  git -C \"$TARGET_ABS\" diff"
fi
