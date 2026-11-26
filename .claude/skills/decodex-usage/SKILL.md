---
name: decodex-usage
description: "Trigger: /decodex-usage, usage, consumo, sesiones, costos, tokens, métricas de Claude. Extract raw Claude Code (Desktop & CLI) session telemetry — sessions, costs, tokens (input/output/cache/thinking), tools used with per-call duration, session durations, models, and effort levels — into a clean JSON file ready for downstream HTML report generation."
compatibility: Requires python3 (3.9+, standard library only) OR built-in macOS osascript (JXA, zero dev tools required). Works on macOS, Windows, and Linux.
metadata:
  version: "0.1.0"
---

# Decodex Usage Extractor

Extract full raw telemetry from local Claude Code (Desktop and CLI) sessions into a single JSON file in `usage-reports/`, including user prompts, per-request model/effort/token traces, assistant responses, and per-tool inputs, outputs, and execution durations.

## Hard Rules

- Never write output files inside `.claude/` (protected by harness hooks); always write to `usage-reports/` or the path explicitly requested by the user.
- Decodex `chatToken` values (`ct1_...`) are automatically redacted by the script; never print or expose them.
- Do not open or re-read the generated JSON file after the script runs; rely on `--print-summary` stdout to report results to the user.
- Do not generate an HTML report unless the user explicitly asks for one after extraction.

## Steps

### 1. Resolve scope (default: general)

Determine `--scope` directly from the user's message (do not ask unless the request is ambiguous):
- **Current session (`session`)**: user says "current session", "sesión actual", "esta sesión", "this session", or `--scope session`.
- **Current project (`project`)**: user says "proyecto", "este proyecto", "proyecto actual", "esta marca", "project", or `--scope project`.
- **General (`all`, default)**: anything else, including running `/decodex-usage` with no arguments, or saying "general", "todas", "todo", "máquina", "all", `--all`, or `--scope all`.

### 2. Resolve engine (default: auto)

Determine `--engine` directly from the user's message:
- **Auto (`auto`, default)**: tries Python first and falls back to macOS JXA (`js`) if Python is unavailable or fails.
- **Python (`python`)**: user says "python", "con python", or `--engine python`.
- **JavaScript / JXA (`js`)**: user says "js", "javascript", "jxa", "sin python", "osascript", or `--engine js`.

### 3. Map optional filters

If the user mentioned filters, pass them through:
- Date lower bound (e.g. "desde 2026-11-01", `--since`) → `--since YYYY-MM-DD`
- Date upper bound (e.g. "hasta 2026-11-24", `--until`) → `--until YYYY-MM-DD`
- Client filter (e.g. "solo Desktop", `--entrypoint claude-desktop`) → `--entrypoint claude-desktop|cli|sdk-ts|all`
- Compact mode (`--compact`, omits per-call tool array) → `--compact`
- Custom output path (`--out <path>`) → `--out <path>`

### 4. Run the extractor

Run once via the unified shell launcher:

```bash
bash "${CLAUDE_PROJECT_DIR:-.}/.claude/skills/decodex-usage/scripts/extract_usage.sh" \
  --scope <all|project|session> \
  --engine <auto|python|js> \
  --project-dir "${CLAUDE_PROJECT_DIR:-.}" \
  --print-summary
```

Add any mapped optional flags from step 3.

### 5. Report the result

From the compact JSON printed to stdout, reply concisely in Spanish with:
- Exact path of the generated JSON file (`outputFile`).
- Quick headline numbers: sessions count (and how many from Desktop), date range, total cost USD (noting native vs estimated sessions), total tokens (input, output, cache read, cache creation), top models, effort levels detected, and top 3–5 tools by call count.
- If `sessionsCount` is `0`, explain plainly that no sessions matched the chosen scope/filters and suggest running again with the general scope (`--scope all`) or a wider date range.

## Output Schema

See `.claude/skills/decodex-usage/references/schema.md` for the full JSON structure consumed by downstream HTML generators.
