#!/usr/bin/env python3
"""
Extract raw Claude Code (Desktop & CLI) session telemetry into a structured JSON
report designed for downstream analysis and HTML dashboard generation.

Standard library only (Python 3.9+, macOS/Linux/Windows).
Includes full session detail by default: user prompts, assistant responses,
per-request tokens/model/effort, and per-tool inputs/outputs/durations.
Decodex chatToken values (`ct1_...`) are automatically redacted.
"""

from __future__ import annotations

import argparse
import glob
import json
import math
import os
import platform
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

SCHEMA_VERSION = "1.1.0"
CHAT_TOKEN_RE = re.compile(r"\bct1_[A-Za-z0-9._-]{8,}\b")


def redact_secrets_str(text: str) -> str:
    return CHAT_TOKEN_RE.sub("[REDACTED_CHAT_TOKEN]", text)


def sanitize_value(val: Any) -> Any:
    if isinstance(val, str):
        return redact_secrets_str(val)
    if isinstance(val, list):
        return [sanitize_value(v) for v in val]
    if isinstance(val, dict):
        out: Dict[str, Any] = {}
        for k, v in val.items():
            if k == "chatToken" and isinstance(v, str):
                out[k] = "[REDACTED_CHAT_TOKEN]"
            else:
                out[k] = sanitize_value(v)
        return out
    return val


def extract_text_from_content(content: Any) -> str:
    if isinstance(content, str):
        return redact_secrets_str(content)
    if isinstance(content, list):
        parts: List[str] = []
        for block in content:
            if isinstance(block, str):
                parts.append(block)
            elif isinstance(block, dict):
                btype = block.get("type")
                if btype == "text" and isinstance(block.get("text"), str):
                    parts.append(block["text"])
        return redact_secrets_str("\n".join(parts).strip())
    return ""


def truncate_text(text: str, max_chars: int) -> Tuple[str, bool]:
    if max_chars <= 0 or len(text) <= max_chars:
        return text, False
    return text[:max_chars] + f"... [truncated {len(text) - max_chars} chars]", True

# Fallback USD pricing per 1M tokens when a session has no native `cost-state` record.
# Verified against Anthropic Claude API pricing (2026) and native Claude Code `cost-state`.
# Keys are matched by prefix (longest match wins).
# Format: (input, output, cache_read, cache_write_5m, cache_write_1h)
MODEL_PRICING_PER_M: Dict[str, Tuple[float, float, float, float, float]] = {
    "claude-opus-5-5": (4.0, 20.0, 0.20, 5.0, 8.0),
    "claude-opus-5": (5.0, 25.0, 0.50, 6.25, 10.0),
    "claude-opus-4-8": (5.0, 25.0, 0.50, 6.25, 10.0),
    "claude-opus-4-6": (5.0, 25.0, 0.50, 6.25, 10.0),
    "claude-opus-4-5": (5.0, 25.0, 0.50, 6.25, 10.0),
    "claude-opus-4": (15.0, 75.0, 1.50, 18.75, 30.0),
    "claude-sonnet-5-5": (2.0, 10.0, 0.10, 2.50, 4.0),
    "claude-sonnet-5": (2.0, 10.0, 0.10, 2.50, 4.0),
    "claude-sonnet-4-6": (3.0, 15.0, 0.30, 3.75, 6.0),
    "claude-sonnet-4-5": (3.0, 15.0, 0.30, 3.75, 6.0),
    "claude-sonnet-4": (3.0, 15.0, 0.30, 3.75, 6.0),
    "claude-3-7-sonnet": (3.0, 15.0, 0.30, 3.75, 6.0),
    "claude-3-5-sonnet": (3.0, 15.0, 0.30, 3.75, 6.0),
    "claude-haiku-5-5": (0.10, 0.50, 0.01, 0.125, 0.20),
    "claude-haiku-5": (0.10, 0.50, 0.01, 0.125, 0.20),
    "claude-haiku-4-5": (1.0, 5.0, 0.10, 1.25, 2.0),
    "claude-haiku-4": (1.0, 5.0, 0.10, 1.25, 2.0),
    "claude-3-5-haiku": (0.80, 4.0, 0.08, 1.0, 1.6),
    "claude-3-haiku": (0.25, 1.25, 0.03, 0.30, 0.50),
    "claude-fable-5-2": (8.0, 40.0, 0.20, 10.0, 16.0),
    "claude-fable-5-1": (10.0, 50.0, 0.25, 12.50, 20.0),
    "claude-fable-5": (10.0, 50.0, 0.25, 12.50, 20.0),
}


def parse_iso_ts(value: Optional[str]) -> Optional[datetime]:
    if not value or not isinstance(value, str):
        return None
    try:
        v = value.strip()
        if v.endswith("Z"):
            v = v[:-1] + "+00:00"
        dt = datetime.fromisoformat(v)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    except ValueError:
        return None


def ms_to_iso(ms: Optional[Any]) -> Optional[str]:
    if not isinstance(ms, (int, float)) or ms <= 0:
        return None
    try:
        return datetime.fromtimestamp(ms / 1000.0, tz=timezone.utc).isoformat().replace("+00:00", "Z")
    except (OverflowError, OSError, ValueError):
        return None


def dt_to_iso(dt: Optional[datetime]) -> Optional[str]:
    if dt is None:
        return None
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_date_filter(date_str: Optional[str], end_of_day: bool = False) -> Optional[datetime]:
    if not date_str:
        return None
    dt = parse_iso_ts(date_str)
    if dt is not None:
        return dt
    try:
        base = datetime.strptime(date_str.strip(), "%Y-%m-%d").replace(tzinfo=timezone.utc)
        if end_of_day:
            return base.replace(hour=23, minute=59, second=59, microsecond=999999)
        return base
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"Invalid date '{date_str}'. Use YYYY-MM-DD or ISO-8601.") from exc


def normalize_path(path_str: Optional[str]) -> Optional[str]:
    if not path_str or not isinstance(path_str, str):
        return None
    try:
        expanded = os.path.expanduser(path_str)
        real = os.path.realpath(expanded)
        return os.path.normcase(os.path.normpath(real))
    except OSError:
        return os.path.normcase(os.path.normpath(path_str))


def path_matches_project(candidate_cwd: Optional[str], project_norm: str) -> bool:
    cand = normalize_path(candidate_cwd)
    if not cand:
        return False
    if cand == project_norm:
        return True
    sep = os.sep
    return cand.startswith(project_norm.rstrip(sep) + sep)


def get_claude_config_dir() -> Path:
    env_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    if env_dir:
        return Path(os.path.expanduser(env_dir))
    return Path.home() / ".claude"


def get_claude_desktop_sessions_dirs() -> List[Path]:
    system = platform.system()
    candidates: List[Path] = []
    if system == "Darwin":
        candidates.append(Path.home() / "Library" / "Application Support" / "Claude" / "claude-code-sessions")
    elif system == "Windows":
        appdata = os.environ.get("APPDATA")
        if appdata:
            candidates.append(Path(appdata) / "Claude" / "claude-code-sessions")
    else:
        xdg = os.environ.get("XDG_CONFIG_HOME")
        if xdg:
            candidates.append(Path(xdg) / "Claude" / "claude-code-sessions")
        candidates.append(Path.home() / ".config" / "Claude" / "claude-code-sessions")
    return [p for p in candidates if p.is_dir()]


def load_desktop_sessions_index() -> Dict[str, Dict[str, Any]]:
    """
    Index Claude Code Desktop session metadata files by cliSessionId (and by sessionId as fallback).
    """
    by_cli_id: Dict[str, Dict[str, Any]] = {}
    for base_dir in get_claude_desktop_sessions_dirs():
        pattern = str(base_dir / "*" / "*" / "local_*.json")
        for filepath in glob.glob(pattern):
            try:
                with open(filepath, "r", encoding="utf-8") as fh:
                    data = json.load(fh)
            except (OSError, json.JSONDecodeError):
                continue
            if not isinstance(data, dict):
                continue
            cli_id = data.get("cliSessionId")
            entry = {
                "desktopSessionId": data.get("sessionId"),
                "cliSessionId": cli_id,
                "cwd": data.get("cwd") or data.get("originCwd"),
                "originCwd": data.get("originCwd"),
                "title": data.get("title"),
                "model": data.get("model"),
                "effort": data.get("effort"),
                "permissionMode": data.get("permissionMode"),
                "isArchived": bool(data.get("isArchived", False)),
                "createdAt": ms_to_iso(data.get("createdAt")),
                "createdAtMs": data.get("createdAt"),
                "lastActivityAt": ms_to_iso(data.get("lastActivityAt")),
                "lastActivityAtMs": data.get("lastActivityAt"),
                "metadataPath": filepath,
            }
            if isinstance(cli_id, str) and cli_id:
                existing = by_cli_id.get(cli_id)
                if not existing or (entry.get("lastActivityAtMs") or 0) >= (existing.get("lastActivityAtMs") or 0):
                    by_cli_id[cli_id] = entry
    return by_cli_id


def lookup_pricing(model_name: str) -> Optional[Tuple[float, float, float, float, float]]:
    if not model_name:
        return None
    low = model_name.lower()
    best_key = ""
    best_rates: Optional[Tuple[float, float, float, float, float]] = None
    for prefix, rates in MODEL_PRICING_PER_M.items():
        if low.startswith(prefix) and len(prefix) > len(best_key):
            best_key = prefix
            best_rates = rates
    if best_rates:
        return best_rates
    # Generic family fallback (current generation rates)
    if "fable" in low:
        return (8.0, 40.0, 0.20, 10.0, 16.0)
    if "opus" in low:
        return (4.0, 20.0, 0.20, 5.0, 8.0)
    if "sonnet" in low:
        return (2.0, 10.0, 0.10, 2.50, 4.0)
    if "haiku" in low:
        return (0.10, 0.50, 0.01, 0.125, 0.20)
    return None


def estimate_cost_usd(
    model_name: str,
    input_tokens: int,
    output_tokens: int,
    cache_read_tokens: int,
    cache_creation_tokens: int,
    cache_creation_5m: int,
    cache_creation_1h: int,
) -> Optional[float]:
    rates = lookup_pricing(model_name)
    if not rates:
        return None
    in_r, out_r, cr_r, cw5_r, cw1h_r = rates
    # If ephemeral 5m/1h breakdown is available, use exact tiers; otherwise treat cache_creation as 5m.
    if cache_creation_5m > 0 or cache_creation_1h > 0:
        remainder = max(0, cache_creation_tokens - cache_creation_5m - cache_creation_1h)
        cw_cost = (
            (cache_creation_5m + remainder) * cw5_r + cache_creation_1h * cw1h_r
        ) / 1_000_000.0
    else:
        cw_cost = (cache_creation_tokens * cw5_r) / 1_000_000.0

    total = (
        (input_tokens * in_r)
        + (output_tokens * out_r)
        + (cache_read_tokens * cr_r)
    ) / 1_000_000.0 + cw_cost
    return round(total, 6)


def percentile(values: List[int], p: float) -> Optional[int]:
    if not values:
        return None
    ordered = sorted(values)
    idx = max(0, min(len(ordered) - 1, math.ceil((p / 100.0) * len(ordered)) - 1))
    return ordered[idx]


def empty_token_bucket() -> Dict[str, int]:
    return {
        "inputTokens": 0,
        "outputTokens": 0,
        "cacheReadInputTokens": 0,
        "cacheCreationInputTokens": 0,
        "cacheCreation5mInputTokens": 0,
        "cacheCreation1hInputTokens": 0,
        "thinkingTokens": 0,
        "totalTokens": 0,
    }


def finalize_token_bucket(b: Dict[str, int]) -> Dict[str, Any]:
    total = (
        b["inputTokens"]
        + b["outputTokens"]
        + b["cacheReadInputTokens"]
        + b["cacheCreationInputTokens"]
    )
    b["totalTokens"] = total
    denom = b["inputTokens"] + b["cacheReadInputTokens"] + b["cacheCreationInputTokens"]
    cache_hit_rate = round(b["cacheReadInputTokens"] / denom, 4) if denom > 0 else None
    out = dict(b)
    out["cacheHitRate"] = cache_hit_rate
    return out


def aggregate_tool_calls(calls: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    grouped: Dict[str, Dict[str, Any]] = {}
    durations_by_tool: Dict[str, List[int]] = defaultdict(list)

    for call in calls:
        name = call["name"]
        slot = grouped.setdefault(
            name,
            {
                "calls": 0,
                "errors": 0,
                "incomplete": 0,
                "totalDurationMs": 0,
                "avgDurationMs": None,
                "minDurationMs": None,
                "p95DurationMs": None,
                "maxDurationMs": None,
            },
        )
        slot["calls"] += 1
        if call.get("isError"):
            slot["errors"] += 1
        if call.get("status") == "incomplete":
            slot["incomplete"] += 1
        dur = call.get("durationMs")
        if isinstance(dur, int) and dur >= 0:
            slot["totalDurationMs"] += dur
            durations_by_tool[name].append(dur)

    for name, slot in grouped.items():
        durs = durations_by_tool.get(name, [])
        if durs:
            slot["avgDurationMs"] = round(sum(durs) / len(durs), 2)
            slot["minDurationMs"] = min(durs)
            slot["p95DurationMs"] = percentile(durs, 95)
            slot["maxDurationMs"] = max(durs)

    return dict(sorted(grouped.items(), key=lambda kv: (-kv[1]["calls"], kv[0])))


def parse_jsonl_transcript(
    jsonl_path: Path,
    desktop_meta: Optional[Dict[str, Any]] = None,
    compact: bool = False,
    max_output_chars: int = 4000,
) -> Optional[Dict[str, Any]]:
    """
    Parse a single Claude Code JSONL transcript (main session or subagent).
    Deduplicates assistant usage by requestId (or message.id fallback).
    Pairs tool_use and tool_result events by tool_use_id for execution duration,
    and captures full prompts, assistant responses, and tool inputs/outputs unless compact=True.
    """
    session_id = jsonl_path.stem
    cwd: Optional[str] = desktop_meta.get("cwd") if desktop_meta else None
    entrypoint: Optional[str] = None
    git_branch: Optional[str] = None
    claude_version: Optional[str] = None
    ai_title: Optional[str] = None

    first_ts: Optional[datetime] = None
    last_ts: Optional[datetime] = None

    user_messages = 0
    turns_count = 0
    active_turn_ms = 0
    thinking_duration_ms = 0

    # Full prompt log
    prompts: List[Dict[str, Any]] = []

    # Deduplicated assistant requests: req_key -> dict (preserving insertion order)
    requests: Dict[str, Dict[str, Any]] = {}
    synthetic_req_counter = 0

    # Tool tracking: tool_use_id -> call dict
    tool_calls_by_id: Dict[str, Dict[str, Any]] = {}
    tool_call_order: List[str] = []

    # Latest cost-state record in file (if emitted by Claude Code)
    last_cost_state: Optional[Dict[str, Any]] = None

    try:
        with open(jsonl_path, "r", encoding="utf-8", errors="replace") as fh:
            for raw_line in fh:
                raw_line = raw_line.strip()
                if not raw_line:
                    continue
                try:
                    obj = json.loads(raw_line)
                except json.JSONDecodeError:
                    continue
                if not isinstance(obj, dict):
                    continue

                rec_type = obj.get("type")

                # Timestamps
                ts = parse_iso_ts(obj.get("timestamp"))
                if ts is not None:
                    if first_ts is None or ts < first_ts:
                        first_ts = ts
                    if last_ts is None or ts > last_ts:
                        last_ts = ts

                # Metadata fields
                if not cwd and isinstance(obj.get("cwd"), str) and obj["cwd"]:
                    cwd = obj["cwd"]
                if not entrypoint and isinstance(obj.get("entrypoint"), str) and obj["entrypoint"]:
                    entrypoint = obj["entrypoint"]
                if not git_branch and isinstance(obj.get("gitBranch"), str) and obj["gitBranch"]:
                    git_branch = obj["gitBranch"]
                if not claude_version and isinstance(obj.get("version"), str) and obj["version"]:
                    claude_version = obj["version"]
                if rec_type == "ai-title" and isinstance(obj.get("aiTitle"), str):
                    ai_title = obj["aiTitle"]
                elif rec_type == "ai-title" and isinstance(obj.get("title"), str):
                    ai_title = obj["title"]

                # Native cost-state event
                if rec_type == "cost-state":
                    last_cost_state = obj
                    continue

                # Turn duration events
                if rec_type == "system" and obj.get("subtype") == "turn_duration":
                    dur = obj.get("durationMs")
                    if isinstance(dur, (int, float)) and dur >= 0:
                        active_turn_ms += int(dur)
                        turns_count += 1
                    continue

                # Assistant records: tokens, models, effort, thinkingDurationMs, text, tool_use
                if rec_type == "assistant":
                    msg = obj.get("message")
                    if not isinstance(msg, dict):
                        continue

                    td_ms = obj.get("thinkingDurationMs")
                    if isinstance(td_ms, (int, float)) and td_ms > 0:
                        thinking_duration_ms += int(td_ms)

                    model = msg.get("model") or obj.get("requestedModel")
                    effort = obj.get("perTurnEffort") or obj.get("effort")
                    usage = msg.get("usage") if isinstance(msg.get("usage"), dict) else None
                    req_key = obj.get("requestId") or msg.get("id")
                    if not isinstance(req_key, str) or not req_key:
                        synthetic_req_counter += 1
                        req_key = f"anon_{synthetic_req_counter}"

                    content = msg.get("content")
                    chunk_text = extract_text_from_content(content) if not compact else ""

                    if usage is not None:
                        cc = usage.get("cache_creation")
                        cc5 = cc.get("ephemeral_5m_input_tokens", 0) if isinstance(cc, dict) else 0
                        cc1h = cc.get("ephemeral_1h_input_tokens", 0) if isinstance(cc, dict) else 0

                        in_tok = int(usage.get("input_tokens") or 0)
                        out_tok = int(usage.get("output_tokens") or 0)
                        cr_tok = int(usage.get("cache_read_input_tokens") or 0)
                        cw_tok = int(usage.get("cache_creation_input_tokens") or 0)

                        out_details = usage.get("output_tokens_details")
                        think_tok = 0
                        if isinstance(out_details, dict):
                            think_tok = int(out_details.get("thinking_tokens") or out_details.get("reasoning_tokens") or 0)

                        prev = requests.get(req_key)
                        if prev is None:
                            requests[req_key] = {
                                "requestId": req_key,
                                "timestamp": dt_to_iso(ts),
                                "model": model or "unknown",
                                "effort": effort,
                                "thinkingDurationMs": int(td_ms) if isinstance(td_ms, (int, float)) and td_ms > 0 else None,
                                "inputTokens": in_tok,
                                "outputTokens": out_tok,
                                "cacheReadInputTokens": cr_tok,
                                "cacheCreationInputTokens": cw_tok,
                                "cacheCreation5mInputTokens": int(cc5 or 0),
                                "cacheCreation1hInputTokens": int(cc1h or 0),
                                "thinkingTokens": think_tok,
                                "_textParts": [chunk_text] if chunk_text else [],
                                "toolUseIds": [],
                            }
                        else:
                            if out_tok >= prev["outputTokens"]:
                                prev["inputTokens"] = in_tok
                                prev["outputTokens"] = out_tok
                                prev["cacheReadInputTokens"] = cr_tok
                                prev["cacheCreationInputTokens"] = cw_tok
                                prev["cacheCreation5mInputTokens"] = int(cc5 or 0)
                                prev["cacheCreation1hInputTokens"] = int(cc1h or 0)
                                prev["thinkingTokens"] = max(prev["thinkingTokens"], think_tok)
                            if not prev.get("effort") and effort:
                                prev["effort"] = effort
                            if prev.get("model") == "unknown" and model:
                                prev["model"] = model
                            if isinstance(td_ms, (int, float)) and td_ms > 0:
                                prev["thinkingDurationMs"] = (prev.get("thinkingDurationMs") or 0) + int(td_ms)
                            if chunk_text and chunk_text not in prev["_textParts"]:
                                prev["_textParts"].append(chunk_text)

                    if isinstance(content, list):
                        for block in content:
                            if isinstance(block, dict) and block.get("type") == "tool_use":
                                tid = block.get("id")
                                tname = block.get("name") or "unknown"
                                if isinstance(tid, str) and tid and tid not in tool_calls_by_id:
                                    call_entry: Dict[str, Any] = {
                                        "toolUseId": tid,
                                        "requestId": req_key,
                                        "name": tname,
                                        "startedAt": dt_to_iso(ts),
                                        "_startDt": ts,
                                        "endedAt": None,
                                        "durationMs": None,
                                        "isError": False,
                                        "status": "incomplete",
                                    }
                                    if not compact:
                                        call_entry["input"] = sanitize_value(block.get("input"))
                                        call_entry["output"] = None
                                        call_entry["outputTruncated"] = False
                                    tool_calls_by_id[tid] = call_entry
                                    tool_call_order.append(tid)
                                    if req_key in requests and tid not in requests[req_key]["toolUseIds"]:
                                        requests[req_key]["toolUseIds"].append(tid)
                    continue

                # User records: capture prompts + pair tool_result
                if rec_type == "user":
                    msg = obj.get("message")
                    if not isinstance(msg, dict):
                        continue
                    content = msg.get("content")
                    has_tool_result = False
                    if isinstance(content, list):
                        tur = obj.get("toolUseResult")
                        tur_dur = None
                        if isinstance(tur, dict):
                            raw_d = tur.get("durationMs") or tur.get("totalDurationMs")
                            if isinstance(raw_d, (int, float)) and raw_d >= 0:
                                tur_dur = int(raw_d)

                        for block in content:
                            if isinstance(block, dict) and block.get("type") == "tool_result":
                                has_tool_result = True
                                tid = block.get("tool_use_id")
                                if isinstance(tid, str) and tid in tool_calls_by_id:
                                    call = tool_calls_by_id[tid]
                                    call["endedAt"] = dt_to_iso(ts)
                                    call["isError"] = bool(block.get("is_error", False))
                                    call["status"] = "error" if call["isError"] else "ok"
                                    start_dt = call.get("_startDt")
                                    if start_dt is not None and ts is not None:
                                        delta_ms = int(round((ts - start_dt).total_seconds() * 1000.0))
                                        if delta_ms >= 0:
                                            call["durationMs"] = delta_ms
                                    if call["durationMs"] is None and tur_dur is not None:
                                        call["durationMs"] = tur_dur
                                    if not compact:
                                        raw_out = extract_text_from_content(block.get("content"))
                                        out_txt, was_trunc = truncate_text(raw_out, max_output_chars)
                                        call["output"] = out_txt
                                        call["outputTruncated"] = was_trunc
                    if not has_tool_result and not obj.get("isMeta"):
                        user_messages += 1
                        if not compact:
                            prompt_text = extract_text_from_content(content)
                            if prompt_text:
                                prompts.append(
                                    {
                                        "index": user_messages,
                                        "uuid": obj.get("uuid"),
                                        "timestamp": dt_to_iso(ts),
                                        "text": prompt_text,
                                    }
                                )
    except OSError:
        return None

    # Ignore completely empty/stub transcripts with no activity
    if not requests and not tool_call_order and last_cost_state is None and user_messages == 0:
        return None

    # Aggregate tokens, models, and effort from deduplicated requests
    tokens_total = empty_token_bucket()
    by_model: Dict[str, Dict[str, Any]] = {}
    by_effort: Dict[str, Dict[str, Any]] = {}

    desktop_effort = desktop_meta.get("effort") if desktop_meta else None

    for req in requests.values():
        m = req["model"] or "unknown"
        eff = req["effort"] or desktop_effort or "unspecified"

        for k in (
            "inputTokens",
            "outputTokens",
            "cacheReadInputTokens",
            "cacheCreationInputTokens",
            "cacheCreation5mInputTokens",
            "cacheCreation1hInputTokens",
            "thinkingTokens",
        ):
            tokens_total[k] += req[k]

        mslot = by_model.setdefault(
            m,
            {
                "requests": 0,
                "tokens": empty_token_bucket(),
                "costUSD": None,
                "costSource": "estimated",
            },
        )
        mslot["requests"] += 1
        for k in (
            "inputTokens",
            "outputTokens",
            "cacheReadInputTokens",
            "cacheCreationInputTokens",
            "cacheCreation5mInputTokens",
            "cacheCreation1hInputTokens",
            "thinkingTokens",
        ):
            mslot["tokens"][k] += req[k]

        eslot = by_effort.setdefault(
            eff,
            {
                "requests": 0,
                "tokens": empty_token_bucket(),
            },
        )
        eslot["requests"] += 1
        for k in (
            "inputTokens",
            "outputTokens",
            "cacheReadInputTokens",
            "cacheCreationInputTokens",
            "cacheCreation5mInputTokens",
            "cacheCreation1hInputTokens",
            "thinkingTokens",
        ):
            eslot["tokens"][k] += req[k]

    # Reconcile native cost-state (if present) vs estimated cost
    cost_source = "estimated"
    total_cost_usd: Optional[float] = None
    cost_by_model: Dict[str, Dict[str, Any]] = {}

    if last_cost_state and isinstance(last_cost_state.get("totalCostUSD"), (int, float)):
        cost_source = "native"
        total_cost_usd = round(float(last_cost_state["totalCostUSD"]), 6)
        native_mu = last_cost_state.get("modelUsage")
        if isinstance(native_mu, dict):
            # Merge thinkingTokens from native cost-state if higher than parsed details
            native_thinking_sum = 0
            for m_name, m_data in native_mu.items():
                if not isinstance(m_data, dict):
                    continue
                m_cost = m_data.get("costUSD")
                if isinstance(m_cost, (int, float)):
                    cost_by_model[m_name] = {
                        "costUSD": round(float(m_cost), 6),
                        "source": "native",
                    }
                    if m_name in by_model:
                        by_model[m_name]["costUSD"] = round(float(m_cost), 6)
                        by_model[m_name]["costSource"] = "native"
                t_tok = int(m_data.get("thinkingTokens") or 0)
                native_thinking_sum += t_tok
                if m_name in by_model and t_tok > by_model[m_name]["tokens"]["thinkingTokens"]:
                    by_model[m_name]["tokens"]["thinkingTokens"] = t_tok
            if native_thinking_sum > tokens_total["thinkingTokens"]:
                tokens_total["thinkingTokens"] = native_thinking_sum
    else:
        est_sum = 0.0
        any_est = False
        for m_name, mslot in by_model.items():
            tb = mslot["tokens"]
            est = estimate_cost_usd(
                m_name,
                tb["inputTokens"],
                tb["outputTokens"],
                tb["cacheReadInputTokens"],
                tb["cacheCreationInputTokens"],
                tb["cacheCreation5mInputTokens"],
                tb["cacheCreation1hInputTokens"],
            )
            mslot["costUSD"] = est
            mslot["costSource"] = "estimated" if est is not None else "unknown"
            if est is not None:
                est_sum += est
                any_est = True
                cost_by_model[m_name] = {"costUSD": est, "source": "estimated"}
        if any_est:
            total_cost_usd = round(est_sum, 6)
        else:
            cost_source = "unknown"

    # Finalize token buckets
    tokens_summary = finalize_token_bucket(tokens_total)
    for mslot in by_model.values():
        mslot["tokens"] = finalize_token_bucket(mslot["tokens"])
    for eslot in by_effort.values():
        eslot["tokens"] = finalize_token_bucket(eslot["tokens"])

    # Clean internal keys from tool calls
    calls_clean: List[Dict[str, Any]] = []
    measured_tool_ms = 0
    for tid in tool_call_order:
        c = dict(tool_calls_by_id[tid])
        c.pop("_startDt", None)
        if isinstance(c.get("durationMs"), int):
            measured_tool_ms += c["durationMs"]
        calls_clean.append(c)

    by_tool = aggregate_tool_calls(calls_clean)

    # Durations
    started_iso = (desktop_meta.get("createdAt") if desktop_meta else None) or dt_to_iso(first_ts)
    ended_iso = dt_to_iso(last_ts) or (desktop_meta.get("lastActivityAt") if desktop_meta else None)

    wall_clock_ms: Optional[int] = None
    if last_cost_state and isinstance(last_cost_state.get("totalDuration"), (int, float)):
        wall_clock_ms = int(last_cost_state["totalDuration"])
    elif first_ts is not None and last_ts is not None:
        wall_clock_ms = max(0, int(round((last_ts - first_ts).total_seconds() * 1000.0)))
    elif desktop_meta and desktop_meta.get("createdAtMs") and desktop_meta.get("lastActivityAtMs"):
        wall_clock_ms = max(0, int(desktop_meta["lastActivityAtMs"] - desktop_meta["createdAtMs"]))

    api_duration_ms: Optional[int] = None
    if last_cost_state and isinstance(last_cost_state.get("totalAPIDuration"), (int, float)):
        api_duration_ms = int(last_cost_state["totalAPIDuration"])

    tool_duration_ms: int = measured_tool_ms
    if last_cost_state and isinstance(last_cost_state.get("totalToolDuration"), (int, float)):
        tool_duration_ms = int(last_cost_state["totalToolDuration"])

    # Primary model (by request count, fallback to desktop metadata)
    models_sorted = sorted(by_model.keys(), key=lambda m: (-by_model[m]["requests"], m))
    primary_model = models_sorted[0] if models_sorted else (desktop_meta.get("model") if desktop_meta else None)

    efforts_sorted = sorted(by_effort.keys(), key=lambda e: (-by_effort[e]["requests"], e))
    resolved_entrypoint = entrypoint or ("claude-desktop" if desktop_meta else "unknown")

    requests_detail: List[Dict[str, Any]] = []
    if not compact:
        for req in requests.values():
            raw_resp = "\n".join(req.get("_textParts") or []).strip()
            resp_txt, resp_trunc = truncate_text(raw_resp, max_output_chars)
            req_tokens = finalize_token_bucket(
                {
                    "inputTokens": req["inputTokens"],
                    "outputTokens": req["outputTokens"],
                    "cacheReadInputTokens": req["cacheReadInputTokens"],
                    "cacheCreationInputTokens": req["cacheCreationInputTokens"],
                    "cacheCreation5mInputTokens": req["cacheCreation5mInputTokens"],
                    "cacheCreation1hInputTokens": req["cacheCreation1hInputTokens"],
                    "thinkingTokens": req["thinkingTokens"],
                    "totalTokens": 0,
                }
            )
            requests_detail.append(
                {
                    "requestId": req["requestId"],
                    "timestamp": req["timestamp"],
                    "model": req["model"],
                    "effort": req["effort"] or desktop_effort or "unspecified",
                    "thinkingDurationMs": req["thinkingDurationMs"],
                    "tokens": req_tokens,
                    "toolUseIds": req["toolUseIds"],
                    "responseText": resp_txt if resp_txt else None,
                    "responseTruncated": resp_trunc,
                }
            )

    session_obj: Dict[str, Any] = {
        "sessionId": session_id,
        "desktopSessionId": desktop_meta.get("desktopSessionId") if desktop_meta else None,
        "title": (desktop_meta.get("title") if desktop_meta else None) or ai_title,
        "cwd": cwd,
        "projectName": os.path.basename(cwd.rstrip(os.sep)) if cwd else None,
        "entrypoint": resolved_entrypoint,
        "isDesktop": resolved_entrypoint == "claude-desktop" or desktop_meta is not None,
        "permissionMode": desktop_meta.get("permissionMode") if desktop_meta else None,
        "isArchived": desktop_meta.get("isArchived") if desktop_meta else False,
        "gitBranch": git_branch,
        "claudeCodeVersion": claude_version,
        "startedAt": started_iso,
        "endedAt": ended_iso,
        "activity": {
            "userMessages": user_messages,
            "assistantRequests": len(requests),
            "turns": turns_count,
            "toolCalls": len(calls_clean),
            "toolErrors": sum(1 for c in calls_clean if c.get("isError")),
        },
        "duration": {
            "wallClockMs": wall_clock_ms,
            "activeTurnMs": active_turn_ms if active_turn_ms > 0 else None,
            "apiDurationMs": api_duration_ms,
            "toolDurationMs": tool_duration_ms,
            "measuredToolDurationMs": measured_tool_ms,
            "thinkingDurationMs": thinking_duration_ms if thinking_duration_ms > 0 else None,
        },
        "primaryModel": primary_model,
        "modelsUsed": models_sorted,
        "desktopEffort": desktop_effort,
        "effortsUsed": efforts_sorted,
        "tokens": tokens_summary,
        "cost": {
            "totalUSD": total_cost_usd,
            "source": cost_source,
            "byModel": cost_by_model,
        },
        "byModel": by_model,
        "byEffort": by_effort,
        "tools": {
            "summary": by_tool,
            **({} if compact else {"calls": calls_clean}),
        },
        **({} if compact else {"prompts": prompts, "requests": requests_detail}),
        "_transcriptPath": str(jsonl_path),
    }
    return session_obj


def parse_subagents(
    main_jsonl: Path,
    compact: bool = False,
    max_output_chars: int = 4000,
) -> List[Dict[str, Any]]:
    sub_dir = main_jsonl.parent / main_jsonl.stem / "subagents"
    if not sub_dir.is_dir():
        return []
    subagents: List[Dict[str, Any]] = []
    for sub_path in sorted(sub_dir.glob("*.jsonl")):
        parsed = parse_jsonl_transcript(
            sub_path,
            desktop_meta=None,
            compact=compact,
            max_output_chars=max_output_chars,
        )
        if not parsed:
            continue
        parsed.pop("_transcriptPath", None)
        sub_entry: Dict[str, Any] = {
            "subagentId": sub_path.stem,
            "startedAt": parsed["startedAt"],
            "endedAt": parsed["endedAt"],
            "primaryModel": parsed["primaryModel"],
            "modelsUsed": parsed["modelsUsed"],
            "effortsUsed": parsed["effortsUsed"],
            "activity": parsed["activity"],
            "duration": parsed["duration"],
            "tokens": parsed["tokens"],
            "cost": parsed["cost"],
            "tools": parsed["tools"],
        }
        if not compact:
            sub_entry["prompts"] = parsed.get("prompts", [])
            sub_entry["requests"] = parsed.get("requests", [])
        subagents.append(sub_entry)
    return subagents


def build_global_summary(sessions: List[Dict[str, Any]]) -> Dict[str, Any]:
    tokens_total = empty_token_bucket()
    by_model: Dict[str, Dict[str, Any]] = {}
    by_effort: Dict[str, Dict[str, Any]] = {}
    by_entrypoint: Dict[str, int] = defaultdict(int)
    by_project: Dict[str, Dict[str, Any]] = {}
    all_tool_calls: List[Dict[str, Any]] = []
    tool_agg_fallback: Dict[str, Dict[str, Any]] = {}

    total_cost_usd = 0.0
    native_cost_sessions = 0
    estimated_cost_sessions = 0
    unknown_cost_sessions = 0

    total_wall_ms = 0
    total_active_ms = 0
    total_api_ms = 0
    total_tool_ms = 0
    total_thinking_ms = 0
    total_requests = 0
    total_user_msgs = 0
    total_turns = 0
    total_subagents = 0

    earliest: Optional[str] = None
    latest: Optional[str] = None

    for s in sessions:
        by_entrypoint[s.get("entrypoint") or "unknown"] += 1
        total_requests += s["activity"]["assistantRequests"]
        total_user_msgs += s["activity"]["userMessages"]
        total_turns += s["activity"]["turns"]
        total_subagents += s.get("subagentsCount", 0)

        st = s.get("startedAt")
        en = s.get("endedAt")
        if st and (earliest is None or st < earliest):
            earliest = st
        if en and (latest is None or en > latest):
            latest = en

        d = s["duration"]
        if isinstance(d.get("wallClockMs"), int):
            total_wall_ms += d["wallClockMs"]
        if isinstance(d.get("activeTurnMs"), int):
            total_active_ms += d["activeTurnMs"]
        if isinstance(d.get("apiDurationMs"), int):
            total_api_ms += d["apiDurationMs"]
        if isinstance(d.get("toolDurationMs"), int):
            total_tool_ms += d["toolDurationMs"]
        if isinstance(d.get("thinkingDurationMs"), int):
            total_thinking_ms += d["thinkingDurationMs"]

        # Tokens
        tb = s["tokens"]
        for k in (
            "inputTokens",
            "outputTokens",
            "cacheReadInputTokens",
            "cacheCreationInputTokens",
            "cacheCreation5mInputTokens",
            "cacheCreation1hInputTokens",
            "thinkingTokens",
        ):
            tokens_total[k] += tb.get(k, 0)

        # Costs
        c_src = s["cost"]["source"]
        c_val = s["cost"]["totalUSD"]
        if c_src == "native":
            native_cost_sessions += 1
        elif c_src == "estimated":
            estimated_cost_sessions += 1
        else:
            unknown_cost_sessions += 1
        if isinstance(c_val, (int, float)):
            total_cost_usd += float(c_val)

        # By project
        proj_key = s.get("cwd") or "unknown"
        pslot = by_project.setdefault(
            proj_key,
            {
                "projectName": s.get("projectName") or "unknown",
                "sessions": 0,
                "costUSD": 0.0,
                "totalTokens": 0,
                "toolCalls": 0,
            },
        )
        pslot["sessions"] += 1
        pslot["costUSD"] = round(pslot["costUSD"] + float(c_val or 0.0), 6)
        pslot["totalTokens"] += tb.get("totalTokens", 0)
        pslot["toolCalls"] += s["activity"]["toolCalls"]

        # By model
        for m_name, mdata in s["byModel"].items():
            mslot = by_model.setdefault(
                m_name,
                {
                    "sessions": 0,
                    "requests": 0,
                    "tokens": empty_token_bucket(),
                    "costUSD": 0.0,
                },
            )
            mslot["sessions"] += 1
            mslot["requests"] += mdata["requests"]
            for k in (
                "inputTokens",
                "outputTokens",
                "cacheReadInputTokens",
                "cacheCreationInputTokens",
                "cacheCreation5mInputTokens",
                "cacheCreation1hInputTokens",
                "thinkingTokens",
            ):
                mslot["tokens"][k] += mdata["tokens"].get(k, 0)
            if isinstance(mdata.get("costUSD"), (int, float)):
                mslot["costUSD"] = round(mslot["costUSD"] + float(mdata["costUSD"]), 6)

        # By effort
        for e_name, edata in s["byEffort"].items():
            eslot = by_effort.setdefault(
                e_name,
                {
                    "sessions": 0,
                    "requests": 0,
                    "tokens": empty_token_bucket(),
                },
            )
            eslot["sessions"] += 1
            eslot["requests"] += edata["requests"]
            for k in (
                "inputTokens",
                "outputTokens",
                "cacheReadInputTokens",
                "cacheCreationInputTokens",
                "cacheCreation5mInputTokens",
                "cacheCreation1hInputTokens",
                "thinkingTokens",
            ):
                eslot["tokens"][k] += edata["tokens"].get(k, 0)

        # Tools
        calls = s["tools"].get("calls")
        if isinstance(calls, list):
            all_tool_calls.extend(calls)
        else:
            for tname, tdata in s["tools"]["summary"].items():
                slot = tool_agg_fallback.setdefault(
                    tname,
                    {"calls": 0, "errors": 0, "incomplete": 0, "totalDurationMs": 0},
                )
                slot["calls"] += tdata["calls"]
                slot["errors"] += tdata["errors"]
                slot["incomplete"] += tdata["incomplete"]
                slot["totalDurationMs"] += tdata["totalDurationMs"]

    for mslot in by_model.values():
        mslot["tokens"] = finalize_token_bucket(mslot["tokens"])
    for eslot in by_effort.values():
        eslot["tokens"] = finalize_token_bucket(eslot["tokens"])

    if all_tool_calls:
        by_tool = aggregate_tool_calls(all_tool_calls)
    else:
        for slot in tool_agg_fallback.values():
            completed = slot["calls"] - slot["incomplete"]
            slot["avgDurationMs"] = round(slot["totalDurationMs"] / completed, 2) if completed > 0 else None
        by_tool = dict(sorted(tool_agg_fallback.items(), key=lambda kv: (-kv[1]["calls"], kv[0])))

    return {
        "sessionsCount": len(sessions),
        "desktopSessionsCount": sum(1 for s in sessions if s.get("isDesktop")),
        "subagentsCount": total_subagents,
        "dateRange": {
            "earliest": earliest,
            "latest": latest,
        },
        "activity": {
            "userMessages": total_user_msgs,
            "assistantRequests": total_requests,
            "turns": total_turns,
            "toolCalls": sum(t["calls"] for t in by_tool.values()),
            "toolErrors": sum(t["errors"] for t in by_tool.values()),
        },
        "duration": {
            "totalWallClockMs": total_wall_ms,
            "totalActiveTurnMs": total_active_ms,
            "totalApiDurationMs": total_api_ms,
            "totalToolDurationMs": total_tool_ms,
            "totalThinkingDurationMs": total_thinking_ms,
        },
        "tokens": finalize_token_bucket(tokens_total),
        "cost": {
            "totalUSD": round(total_cost_usd, 6),
            "nativeSessions": native_cost_sessions,
            "estimatedSessions": estimated_cost_sessions,
            "unknownSessions": unknown_cost_sessions,
        },
        "byEntrypoint": dict(sorted(by_entrypoint.items())),
        "byModel": dict(sorted(by_model.items(), key=lambda kv: (-kv[1]["requests"], kv[0]))),
        "byEffort": dict(sorted(by_effort.items(), key=lambda kv: (-kv[1]["requests"], kv[0]))),
        "byTool": by_tool,
        "byProject": dict(sorted(by_project.items(), key=lambda kv: (-kv[1]["sessions"], kv[0]))),
    }


def collect_sessions(
    scope: str,
    project_dir: Path,
    since_dt: Optional[datetime],
    until_dt: Optional[datetime],
    entrypoint_filter: str,
    include_subagents: bool,
    compact: bool,
    session_id_override: Optional[str] = None,
    max_output_chars: int = 4000,
) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    config_dir = get_claude_config_dir()
    projects_dir = config_dir / "projects"
    desktop_index = load_desktop_sessions_index()
    project_norm = normalize_path(str(project_dir)) or ""

    jsonl_files = sorted(projects_dir.glob("*/*.jsonl")) if projects_dir.is_dir() else []

    if scope == "session":
        target_sid = session_id_override or os.environ.get("CLAUDE_SESSION_ID")
        if target_sid:
            jsonl_files = [p for p in jsonl_files if p.stem == target_sid]
        else:
            # Pick the most recently modified transcript for this project (fallback: newest overall).
            def _mtime(p: Path) -> float:
                try:
                    return p.stat().st_mtime
                except OSError:
                    return 0.0

            ordered = sorted(jsonl_files, key=_mtime, reverse=True)
            chosen: Optional[Path] = None
            for cand in ordered:
                dm = desktop_index.get(cand.stem)
                if dm and path_matches_project(dm.get("cwd"), project_norm):
                    chosen = cand
                    break
                # Quick head scan for cwd in JSONL
                try:
                    with open(cand, "r", encoding="utf-8", errors="replace") as fh:
                        for idx, line in enumerate(fh):
                            if idx > 25:
                                break
                            try:
                                rec = json.loads(line)
                            except json.JSONDecodeError:
                                continue
                            if isinstance(rec, dict) and path_matches_project(rec.get("cwd"), project_norm):
                                chosen = cand
                                break
                except OSError:
                    continue
                if chosen is not None:
                    break
            if chosen is None and ordered:
                chosen = ordered[0]
            jsonl_files = [chosen] if chosen else []

    sessions: List[Dict[str, Any]] = []
    seen_ids = set()

    for jpath in jsonl_files:
        sid = jpath.stem
        desktop_meta = desktop_index.get(sid)

        # Fast pre-filter for project scope using Desktop cwd if available
        if scope == "project" and desktop_meta and desktop_meta.get("cwd"):
            if not path_matches_project(desktop_meta["cwd"], project_norm):
                continue

        parsed = parse_jsonl_transcript(
            jpath,
            desktop_meta=desktop_meta,
            compact=compact,
            max_output_chars=max_output_chars,
        )
        if not parsed:
            continue

        # Enforce project scope on resolved cwd
        if scope == "project":
            if not path_matches_project(parsed.get("cwd"), project_norm):
                continue

        # Entrypoint filter (skip for explicit current-session extraction unless requested)
        if entrypoint_filter != "all":
            if entrypoint_filter == "claude-desktop":
                if not parsed.get("isDesktop"):
                    continue
            elif parsed.get("entrypoint") != entrypoint_filter:
                continue

        # Date range filter (based on endedAt or startedAt)
        ref_dt = parse_iso_ts(parsed.get("endedAt")) or parse_iso_ts(parsed.get("startedAt"))
        if since_dt is not None and (ref_dt is None or ref_dt < since_dt):
            continue
        if until_dt is not None and (ref_dt is None or ref_dt > until_dt):
            continue

        if include_subagents:
            subs = parse_subagents(jpath, compact=compact, max_output_chars=max_output_chars)
            parsed["subagentsCount"] = len(subs)
            parsed["subagents"] = subs
        else:
            parsed["subagentsCount"] = 0
            parsed["subagents"] = []

        parsed.pop("_transcriptPath", None)
        sessions.append(parsed)
        seen_ids.add(sid)

    # Sort newest first
    sessions.sort(key=lambda s: s.get("endedAt") or s.get("startedAt") or "", reverse=True)

    diagnostics = {
        "claudeProjectsDir": str(projects_dir),
        "claudeDesktopSessionsDirs": [str(p) for p in get_claude_desktop_sessions_dirs()],
        "desktopMetadataFilesIndexed": len(desktop_index),
        "transcriptFilesScanned": len(jsonl_files),
    }
    return sessions, diagnostics


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Extract Claude Code (Desktop & CLI) session metrics into raw JSON."
    )
    parser.add_argument(
        "--scope",
        choices=("all", "project", "session"),
        default="all",
        help="Scope: 'all' (default, all sessions on machine), 'project' (current project only), or 'session' (current active session only).",
    )
    parser.add_argument(
        "--session-id",
        default=None,
        help="Explicit session UUID to extract when --scope=session (optional; auto-detects latest session in project).",
    )
    parser.add_argument(
        "--project-dir",
        default=".",
        help="Project root directory used when --scope=project or --scope=session (default: current directory).",
    )
    parser.add_argument(
        "--since",
        default=None,
        help="Include only sessions with activity on or after YYYY-MM-DD (or ISO-8601).",
    )
    parser.add_argument(
        "--until",
        default=None,
        help="Include only sessions with activity on or before YYYY-MM-DD (or ISO-8601).",
    )
    parser.add_argument(
        "--entrypoint",
        choices=("all", "claude-desktop", "cli", "sdk-ts"),
        default="all",
        help="Filter sessions by entrypoint (default: all).",
    )
    parser.add_argument(
        "--no-subagents",
        action="store_true",
        help="Exclude subagent transcripts from each session.",
    )
    parser.add_argument(
        "--compact",
        action="store_true",
        help="Omit prompts, assistant response bodies, per-request traces, and per-call tool arrays (metrics only).",
    )
    parser.add_argument(
        "--max-output-chars",
        type=int,
        default=4000,
        help="Max characters kept per tool output and assistant response text (default: 4000; 0 = unlimited).",
    )
    parser.add_argument(
        "--out",
        default=None,
        help="Output JSON file path. Defaults to ./usage-reports/decodex-usage-<scope>-<timestamp>.json.",
    )
    parser.add_argument(
        "--print-summary",
        action="store_true",
        help="Print a concise JSON summary to stdout after writing the output file.",
    )

    args = parser.parse_args()
    project_dir = Path(os.path.realpath(os.path.expanduser(args.project_dir)))
    since_dt = parse_date_filter(args.since, end_of_day=False)
    until_dt = parse_date_filter(args.until, end_of_day=True)

    sessions, diagnostics = collect_sessions(
        scope=args.scope,
        project_dir=project_dir,
        since_dt=since_dt,
        until_dt=until_dt,
        entrypoint_filter=args.entrypoint,
        include_subagents=not args.no_subagents,
        compact=args.compact,
        session_id_override=args.session_id,
        max_output_chars=args.max_output_chars,
    )

    now_utc = datetime.now(timezone.utc)
    summary = build_global_summary(sessions)

    report: Dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": dt_to_iso(now_utc),
        "scope": args.scope,
        "projectDir": str(project_dir) if args.scope in ("project", "session") else None,
        "filters": {
            "since": args.since,
            "until": args.until,
            "entrypoint": args.entrypoint,
            "includeSubagents": not args.no_subagents,
            "compact": args.compact,
            "maxOutputChars": args.max_output_chars,
        },
        "environment": {
            "os": platform.system(),
            "osRelease": platform.release(),
            "pythonVersion": platform.python_version(),
        },
        "pricingAssumptionsUSDPerMillion": {
            k: {
                "input": v[0],
                "output": v[1],
                "cacheRead": v[2],
                "cacheWrite5m": v[3],
                "cacheWrite1h": v[4],
            }
            for k, v in MODEL_PRICING_PER_M.items()
        },
        "sources": diagnostics,
        "summary": summary,
        "sessions": sessions,
    }

    if args.out:
        out_path = Path(os.path.expanduser(args.out))
    else:
        stamp = now_utc.strftime("%Y%m%d-%H%M%S")
        out_dir = project_dir / "usage-reports"
        out_path = out_dir / f"decodex-usage-{args.scope}-{stamp}.json"

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, ensure_ascii=False)
        fh.write("\n")

    if args.print_summary:
        compact_out = {
            "outputFile": str(out_path),
            "scope": args.scope,
            "sessionsCount": summary["sessionsCount"],
            "desktopSessionsCount": summary["desktopSessionsCount"],
            "subagentsCount": summary["subagentsCount"],
            "dateRange": summary["dateRange"],
            "totalCostUSD": summary["cost"]["totalUSD"],
            "costSources": {
                "native": summary["cost"]["nativeSessions"],
                "estimated": summary["cost"]["estimatedSessions"],
            },
            "tokens": summary["tokens"],
            "duration": summary["duration"],
            "topModels": list(summary["byModel"].keys())[:5],
            "topEfforts": list(summary["byEffort"].keys())[:5],
            "topTools": [
                {"tool": k, "calls": v["calls"], "avgDurationMs": v["avgDurationMs"]}
                for k, v in list(summary["byTool"].items())[:8]
            ],
        }
        print(json.dumps(compact_out, indent=2, ensure_ascii=False))
    else:
        print(str(out_path))

    return 0


if __name__ == "__main__":
    sys.exit(main())
