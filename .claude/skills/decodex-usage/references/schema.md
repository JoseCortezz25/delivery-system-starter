# `decodex-usage` JSON Schema Reference (v1.1.0)

Raw JSON contract emitted by `.claude/skills/decodex-usage/scripts/extract_usage.py`. Designed to be handed directly to another LLM to build interactive HTML reports or dashboards. Includes full session detail (prompts, per-request traces, and per-tool inputs/outputs/durations) unless `--compact` is passed. Decodex `chatToken` values (`ct1_...`) are automatically redacted.

## Top-Level Structure

```json
{
  "schemaVersion": "1.0.0",
  "generatedAt": "2026-11-24T17:30:00.000000Z",
  "scope": "all | project | session",
  "projectDir": "/abs/path/or/null",
  "filters": {
    "since": "YYYY-MM-DD | null",
    "until": "YYYY-MM-DD | null",
    "entrypoint": "all | claude-desktop | cli | sdk-ts",
    "includeSubagents": true,
    "compact": false
  },
  "environment": { "os": "Darwin", "osRelease": "...", "pythonVersion": "3.x.y" },
  "pricingAssumptionsUSDPerMillion": { "<model-prefix>": { "input": 3.0, "output": 15.0, "cacheRead": 0.3, "cacheWrite5m": 3.75, "cacheWrite1h": 6.0 } },
  "sources": {
    "claudeProjectsDir": "...",
    "claudeDesktopSessionsDirs": ["..."],
    "desktopMetadataFilesIndexed": 50,
    "transcriptFilesScanned": 108
  },
  "summary": { ... },
  "sessions": [ ... ]
}
```

## Key Objects

### `tokens` (used in `summary`, `sessions[]`, `byModel`, `byEffort`, `subagents[]`)
- `inputTokens`: non-cached input tokens (deduplicated per `requestId`).
- `outputTokens`: output tokens (deduplicated per `requestId`).
- `cacheReadInputTokens`: prompt cache read tokens.
- `cacheCreationInputTokens`: prompt cache creation tokens.
- `cacheCreation5mInputTokens` / `cacheCreation1hInputTokens`: ephemeral cache tier breakdown when emitted by the API.
- `thinkingTokens`: reasoning/thinking tokens when present (`cost-state` or `output_tokens_details`).
- `totalTokens`: `inputTokens + outputTokens + cacheReadInputTokens + cacheCreationInputTokens`.
- `cacheHitRate`: `cacheReadInputTokens / (inputTokens + cacheReadInputTokens + cacheCreationInputTokens)` (`0..1` or `null`).

### `cost`
- `totalUSD`: total cost in USD (`float | null`).
- `source`: `"native"` (directly from Claude Code's `cost-state` event), `"estimated"` (computed via `pricingAssumptionsUSDPerMillion`), or `"unknown"`.
- `byModel`: map of `modelName -> { costUSD, source }`.

### `duration` (all values in milliseconds)
- `wallClockMs`: total session span (`cost-state.totalDuration`, or `lastTimestamp - firstTimestamp`).
- `activeTurnMs`: sum of `system.turn_duration.durationMs` (active agent execution time, excluding idle gaps).
- `apiDurationMs`: total LLM API time from `cost-state.totalAPIDuration` (if available).
- `toolDurationMs`: total tool execution time (`cost-state.totalToolDuration`, fallback to `measuredToolDurationMs`).
- `measuredToolDurationMs`: sum of paired `tool_result.timestamp - tool_use.timestamp` across all tool calls.
- `thinkingDurationMs`: sum of `assistant.thinkingDurationMs` (if available).

### `tools` (per session) & `summary.byTool`
- `summary`: map of `toolName -> { calls, errors, incomplete, totalDurationMs, avgDurationMs, minDurationMs, p95DurationMs, maxDurationMs }`.
- `calls[]` (omitted when `--compact`): ordered list of `{ toolUseId, requestId, name, input, output, outputTruncated, startedAt, endedAt, durationMs, isError, status }`.

### `prompts[]` (per session, omitted when `--compact`)
- Ordered list of every user prompt in the session: `{ index, uuid, timestamp, text }`.

### `requests[]` (per session, omitted when `--compact`)
- Ordered, deduplicated list of every assistant API request: `{ requestId, timestamp, model, effort, thinkingDurationMs, tokens, toolUseIds[], responseText, responseTruncated }`.

### `byModel` & `byEffort`
- `byModel`: breakdown of `requests`, `tokens`, `costUSD` (and `sessions` in global summary) by exact model ID.
- `byEffort`: breakdown of `requests`, `tokens` (and `sessions` in global summary) by effort level (`low`, `medium`, `high`, `xhigh`, `max`, or `unspecified`).

### `subagents[]` (per session)
- Extracted from `<sessionId>/subagents/*.jsonl` with the same `activity`, `duration`, `tokens`, `cost`, `tools`, `prompts`, `requests`, `modelsUsed`, and `effortsUsed` fields.
