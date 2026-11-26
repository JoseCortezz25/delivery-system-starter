#!/usr/bin/osascript -l JavaScript
/**
 * Extract raw Claude Code (Desktop & CLI) session telemetry into a structured JSON
 * report designed for downstream analysis and HTML dashboard generation.
 *
 * macOS JXA (JavaScript for Automation) engine — zero external dependencies,
 * uses only built-in JavaScriptCore + Foundation/stdlib frameworks.
 * 100% functional and JSON schema parity (v1.1.0) with extract_usage.py.
 */

ObjC.import("Foundation");
ObjC.import("stdlib");

var SCHEMA_VERSION = "1.1.0";
var CHAT_TOKEN_RE = /\bct1_[A-Za-z0-9._-]{8,}\b/g;

// Fallback USD pricing per 1M tokens when a session has no native `cost-state` record.
// Keys are matched by prefix (longest match wins).
// Format: [input, output, cacheRead, cacheWrite5m, cacheWrite1h]
var MODEL_PRICING_PER_M = {
  "claude-opus-5-5": [4.0, 20.0, 0.2, 5.0, 8.0],
  "claude-opus-5": [5.0, 25.0, 0.5, 6.25, 10.0],
  "claude-opus-4-8": [5.0, 25.0, 0.5, 6.25, 10.0],
  "claude-opus-4-6": [5.0, 25.0, 0.5, 6.25, 10.0],
  "claude-opus-4-5": [5.0, 25.0, 0.5, 6.25, 10.0],
  "claude-opus-4": [15.0, 75.0, 1.5, 18.75, 30.0],
  "claude-sonnet-5-5": [2.0, 10.0, 0.1, 2.5, 4.0],
  "claude-sonnet-5": [2.0, 10.0, 0.1, 2.5, 4.0],
  "claude-sonnet-4-6": [3.0, 15.0, 0.3, 3.75, 6.0],
  "claude-sonnet-4-5": [3.0, 15.0, 0.3, 3.75, 6.0],
  "claude-sonnet-4": [3.0, 15.0, 0.3, 3.75, 6.0],
  "claude-3-7-sonnet": [3.0, 15.0, 0.3, 3.75, 6.0],
  "claude-3-5-sonnet": [3.0, 15.0, 0.3, 3.75, 6.0],
  "claude-haiku-5-5": [0.1, 0.5, 0.01, 0.125, 0.2],
  "claude-haiku-5": [0.1, 0.5, 0.01, 0.125, 0.2],
  "claude-haiku-4-5": [1.0, 5.0, 0.1, 1.25, 2.0],
  "claude-haiku-4": [1.0, 5.0, 0.1, 1.25, 2.0],
  "claude-3-5-haiku": [0.8, 4.0, 0.08, 1.0, 1.6],
  "claude-3-haiku": [0.25, 1.25, 0.03, 0.3, 0.5],
  "claude-fable-5-2": [8.0, 40.0, 0.2, 10.0, 16.0],
  "claude-fable-5-1": [10.0, 50.0, 0.25, 12.5, 20.0],
  "claude-fable-5": [10.0, 50.0, 0.25, 12.5, 20.0],
};

var TOKEN_KEYS = [
  "inputTokens",
  "outputTokens",
  "cacheReadInputTokens",
  "cacheCreationInputTokens",
  "cacheCreation5mInputTokens",
  "cacheCreation1hInputTokens",
  "thinkingTokens",
];

var fm = $.NSFileManager.defaultManager;

function writeStdout(text) {
  var data = $(text).dataUsingEncoding($.NSUTF8StringEncoding);
  if (data && !data.isNil()) {
    $.NSFileHandle.fileHandleWithStandardOutput.writeData(data);
  }
}

function writeStderr(text) {
  var data = $(text).dataUsingEncoding($.NSUTF8StringEncoding);
  if (data && !data.isNil()) {
    $.NSFileHandle.fileHandleWithStandardError.writeData(data);
  }
}

function getEnv(name) {
  var val = $.NSProcessInfo.processInfo.environment.objectForKey(name);
  if (!val || val.isNil()) return null;
  var s = ObjC.unwrap(val);
  return typeof s === "string" && s.length > 0 ? s : null;
}

function getHomeDir() {
  return ObjC.unwrap($.NSHomeDirectory());
}

function getCwd() {
  return ObjC.unwrap(fm.currentDirectoryPath);
}

function getOsRelease() {
  var v = $.NSProcessInfo.processInfo.operatingSystemVersion;
  if (v && typeof v.majorVersion === "number") {
    return v.majorVersion + "." + v.minorVersion + "." + v.patchVersion;
  }
  var s = $.NSProcessInfo.processInfo.operatingSystemVersionString;
  return s && !s.isNil() ? ObjC.unwrap(s) : "unknown";
}

function expandUser(pathStr) {
  if (!pathStr || typeof pathStr !== "string") return pathStr;
  if (pathStr === "~") return getHomeDir();
  if (pathStr.indexOf("~/") === 0) return getHomeDir() + pathStr.slice(1);
  return pathStr;
}

function joinPath(a, b) {
  if (!a) return b;
  if (!b) return a;
  if (b.charAt(0) === "/") return b;
  return a.replace(/\/+$/, "") + "/" + b.replace(/^\/+/, "");
}

function dirnamePath(p) {
  var ns = $(p).stringByDeletingLastPathComponent;
  return ns && !ns.isNil() ? ObjC.unwrap(ns) : ".";
}

function basenamePath(p) {
  if (!p) return "";
  var trimmed = p.replace(/\/+$/, "");
  if (!trimmed) return "/";
  var idx = trimmed.lastIndexOf("/");
  return idx >= 0 ? trimmed.slice(idx + 1) : trimmed;
}

function stemPath(p) {
  var base = basenamePath(p);
  var dot = base.lastIndexOf(".");
  return dot > 0 ? base.slice(0, dot) : base;
}

function normPath(p) {
  if (!p || typeof p !== "string") return p;
  var abs = p.charAt(0) === "/";
  var parts = p.split("/");
  var stack = [];
  for (var i = 0; i < parts.length; i++) {
    var seg = parts[i];
    if (!seg || seg === ".") continue;
    if (seg === "..") {
      if (stack.length > 0 && stack[stack.length - 1] !== "..") {
        stack.pop();
      } else if (!abs) {
        stack.push("..");
      }
    } else {
      stack.push(seg);
    }
  }
  var joined = (abs ? "/" : "") + stack.join("/");
  return joined || (abs ? "/" : ".");
}

function resolveRealPath(pathStr) {
  if (!pathStr || typeof pathStr !== "string") return null;
  var expanded = expandUser(pathStr);
  var absPath = expanded.charAt(0) === "/" ? expanded : joinPath(getCwd(), expanded);
  var resolved = absPath;
  try {
    var url = $.NSURL.fileURLWithPath(absPath).URLByResolvingSymlinksInPath;
    if (url && !url.isNil()) {
      var p = url.path;
      if (p && !p.isNil()) {
        resolved = ObjC.unwrap(p);
      }
    }
  } catch (e) {
    // Fall through to lexical normalization
  }
  resolved = normPath(resolved);
  // Cocoa strips /private for root symlinks (/tmp, /var, /etc); match POSIX realpath
  var segs = resolved.split("/");
  if (segs.length > 1 && segs[1]) {
    var topLink = "/" + segs[1];
    var linkErr = Ref();
    var dest = fm.destinationOfSymbolicLinkAtPathError(topLink, linkErr);
    if (dest && !dest.isNil()) {
      var destStr = ObjC.unwrap(dest);
      var targetTop = destStr.charAt(0) === "/" ? destStr : "/" + destStr;
      var rest = segs.slice(2).join("/");
      resolved = normPath(rest ? targetTop + "/" + rest : targetTop);
    }
  }
  return resolved;
}

function normalizePath(pathStr) {
  if (!pathStr || typeof pathStr !== "string") return null;
  return resolveRealPath(pathStr);
}

function pathMatchesProject(candidateCwd, projectNorm) {
  var cand = normalizePath(candidateCwd);
  if (!cand) return false;
  if (cand === projectNorm) return true;
  var prefix = projectNorm.replace(/\/+$/, "") + "/";
  return cand.indexOf(prefix) === 0;
}

function isDir(p) {
  var isDirectory = Ref();
  var exists = fm.fileExistsAtPathIsDirectory(p, isDirectory);
  return Boolean(exists && isDirectory[0]);
}

function listDir(dirPath) {
  var err = Ref();
  var items = fm.contentsOfDirectoryAtPathError(dirPath, err);
  if (!items || items.isNil()) return [];
  var arr = ObjC.unwrap(items);
  if (!Array.isArray(arr)) return [];
  var out = [];
  for (var i = 0; i < arr.length; i++) {
    var v = arr[i];
    out.push(typeof v === "string" ? v : ObjC.unwrap(v));
  }
  return out;
}

function getMtimeMs(filePath) {
  var err = Ref();
  var attrs = fm.attributesOfItemAtPathError(filePath, err);
  if (!attrs || attrs.isNil()) return 0;
  var modDate = attrs.objectForKey($.NSFileModificationDate);
  if (!modDate || modDate.isNil()) return 0;
  return modDate.timeIntervalSince1970 * 1000.0;
}

function readTextFile(filePath) {
  var err = Ref();
  var nsStr = $.NSString.stringWithContentsOfFileEncodingError(
    filePath,
    $.NSUTF8StringEncoding,
    err
  );
  if (nsStr && !nsStr.isNil()) {
    return ObjC.unwrap(nsStr);
  }
  // Lossy fallback for files with invalid UTF-8 byte sequences
  var data = $.NSData.dataWithContentsOfFile(filePath);
  if (!data || data.isNil()) return null;
  var fallback = $.NSString.alloc.initWithDataEncoding(data, $.NSISOLatin1StringEncoding);
  if (!fallback || fallback.isNil()) return null;
  return ObjC.unwrap(fallback);
}

function writeTextFile(filePath, content) {
  var absTarget = filePath.charAt(0) === "/" ? filePath : joinPath(getCwd(), filePath);
  var parentDir = dirnamePath(absTarget);
  var err = Ref();
  fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(
    parentDir,
    true,
    $(),
    err
  );
  var data = $(content).dataUsingEncoding($.NSUTF8StringEncoding);
  if (!data || data.isNil()) {
    throw new Error("Failed to encode UTF-8 output for " + filePath);
  }
  var ok = data.writeToFileAtomically(absTarget, true);
  if (!ok) {
    throw new Error("Failed to write output file: " + filePath);
  }
}

function cmpStr(a, b) {
  return a < b ? -1 : a > b ? 1 : 0;
}

function isPlainObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

function isFiniteNum(v) {
  return typeof v === "number" && isFinite(v);
}

function roundN(n, digits) {
  return Number(n.toFixed(digits)) + 0;
}

function pad2(n) {
  return n < 10 ? "0" + n : String(n);
}

function pad3(n) {
  return n < 10 ? "00" + n : n < 100 ? "0" + n : String(n);
}

function redactSecretsStr(text) {
  return text.replace(CHAT_TOKEN_RE, "[REDACTED_CHAT_TOKEN]");
}

function sanitizeValue(val) {
  if (typeof val === "string") {
    return redactSecretsStr(val);
  }
  if (Array.isArray(val)) {
    var arr = [];
    for (var i = 0; i < val.length; i++) {
      arr.push(sanitizeValue(val[i]));
    }
    return arr;
  }
  if (isPlainObject(val)) {
    var out = {};
    var keys = Object.keys(val);
    for (var k = 0; k < keys.length; k++) {
      var key = keys[k];
      var v = val[key];
      if (key === "chatToken" && typeof v === "string") {
        out[key] = "[REDACTED_CHAT_TOKEN]";
      } else {
        out[key] = sanitizeValue(v);
      }
    }
    return out;
  }
  return val;
}

function extractTextFromContent(content) {
  if (typeof content === "string") {
    return redactSecretsStr(content);
  }
  if (Array.isArray(content)) {
    var parts = [];
    for (var i = 0; i < content.length; i++) {
      var block = content[i];
      if (typeof block === "string") {
        parts.push(block);
      } else if (isPlainObject(block)) {
        if (block.type === "text" && typeof block.text === "string") {
          parts.push(block.text);
        }
      }
    }
    return redactSecretsStr(parts.join("\n").trim());
  }
  return "";
}

function truncateText(text, maxChars) {
  if (maxChars <= 0 || text.length <= maxChars) {
    return [text, false];
  }
  return [
    text.slice(0, maxChars) + "... [truncated " + (text.length - maxChars) + " chars]",
    true,
  ];
}

function parseIsoTs(value) {
  if (!value || typeof value !== "string") return null;
  var v = value.trim();
  if (!v) return null;
  // Normalize space separator to T and append Z if no timezone offset is present
  v = v.replace(" ", "T");
  if (/^\d{4}-\d{2}-\d{2}$/.test(v)) {
    v = v + "T00:00:00Z";
  } else if (!/[zZ]$/.test(v) && !/[+-]\d{2}:?\d{2}$/.test(v)) {
    v = v + "Z";
  }
  // JavaScript Date parses up to milliseconds; trim sub-millisecond fractional digits if present
  v = v.replace(/(\.\d{3})\d+/, "$1");
  var ms = Date.parse(v);
  if (isNaN(ms)) return null;
  return ms;
}

function msToIso(ms) {
  if (!isFiniteNum(ms) || ms <= 0) return null;
  return epochMsToIso(ms);
}

function epochMsToIso(ms) {
  if (ms === null || ms === undefined || !isFiniteNum(ms)) return null;
  var d = new Date(ms);
  if (isNaN(d.getTime())) return null;
  var y = d.getUTCFullYear();
  var mo = pad2(d.getUTCMonth() + 1);
  var da = pad2(d.getUTCDate());
  var h = pad2(d.getUTCHours());
  var mi = pad2(d.getUTCMinutes());
  var s = pad2(d.getUTCSeconds());
  var frac = d.getUTCMilliseconds();
  var base = y + "-" + mo + "-" + da + "T" + h + ":" + mi + ":" + s;
  if (frac === 0) {
    return base + "Z";
  }
  return base + "." + pad3(frac) + "000Z";
}

function parseDateFilter(dateStr, endOfDay) {
  if (!dateStr) return null;
  var trimmed = dateStr.trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    var parts = trimmed.split("-");
    var y = parseInt(parts[0], 10);
    var m = parseInt(parts[1], 10) - 1;
    var d = parseInt(parts[2], 10);
    if (endOfDay) {
      return Date.UTC(y, m, d, 23, 59, 59, 999);
    }
    return Date.UTC(y, m, d, 0, 0, 0, 0);
  }
  var parsed = parseIsoTs(trimmed);
  if (parsed !== null) return parsed;
  throw new Error("Invalid date '" + dateStr + "'. Use YYYY-MM-DD or ISO-8601.");
}

function getClaudeConfigDir() {
  var envDir = getEnv("CLAUDE_CONFIG_DIR");
  if (envDir) {
    return expandUser(envDir);
  }
  return joinPath(getHomeDir(), ".claude");
}

function getClaudeDesktopSessionsDirs() {
  var candidate = joinPath(
    getHomeDir(),
    "Library/Application Support/Claude/claude-code-sessions"
  );
  return isDir(candidate) ? [candidate] : [];
}

function loadDesktopSessionsIndex() {
  var byCliId = {};
  var baseDirs = getClaudeDesktopSessionsDirs();
  for (var b = 0; b < baseDirs.length; b++) {
    var baseDir = baseDirs[b];
    var level1 = listDir(baseDir);
    for (var i = 0; i < level1.length; i++) {
      var d1 = joinPath(baseDir, level1[i]);
      if (!isDir(d1)) continue;
      var level2 = listDir(d1);
      for (var j = 0; j < level2.length; j++) {
        var d2 = joinPath(d1, level2[j]);
        if (!isDir(d2)) continue;
        var files = listDir(d2);
        for (var k = 0; k < files.length; k++) {
          var fname = files[k];
          if (fname.indexOf("local_") !== 0 || fname.slice(-5) !== ".json") continue;
          var filepath = joinPath(d2, fname);
          var raw = readTextFile(filepath);
          if (!raw) continue;
          var data = null;
          try {
            data = JSON.parse(raw);
          } catch (e) {
            continue;
          }
          if (!isPlainObject(data)) continue;
          var cliId = data.cliSessionId;
          var entry = {
            desktopSessionId: data.sessionId !== undefined ? data.sessionId : null,
            cliSessionId: cliId !== undefined ? cliId : null,
            cwd: data.cwd || data.originCwd || null,
            originCwd: data.originCwd !== undefined ? data.originCwd : null,
            title: data.title !== undefined ? data.title : null,
            model: data.model !== undefined ? data.model : null,
            effort: data.effort !== undefined ? data.effort : null,
            permissionMode: data.permissionMode !== undefined ? data.permissionMode : null,
            isArchived: Boolean(data.isArchived),
            createdAt: msToIso(data.createdAt),
            createdAtMs: data.createdAt !== undefined ? data.createdAt : null,
            lastActivityAt: msToIso(data.lastActivityAt),
            lastActivityAtMs: data.lastActivityAt !== undefined ? data.lastActivityAt : null,
            metadataPath: filepath,
          };
          if (typeof cliId === "string" && cliId.length > 0) {
            var existing = byCliId[cliId];
            if (
              !existing ||
              (entry.lastActivityAtMs || 0) >= (existing.lastActivityAtMs || 0)
            ) {
              byCliId[cliId] = entry;
            }
          }
        }
      }
    }
  }
  return byCliId;
}

function lookupPricing(modelName) {
  if (!modelName) return null;
  var low = modelName.toLowerCase();
  var bestKey = "";
  var bestRates = null;
  var prefixes = Object.keys(MODEL_PRICING_PER_M);
  for (var i = 0; i < prefixes.length; i++) {
    var prefix = prefixes[i];
    if (low.indexOf(prefix) === 0 && prefix.length > bestKey.length) {
      bestKey = prefix;
      bestRates = MODEL_PRICING_PER_M[prefix];
    }
  }
  if (bestRates) return bestRates;
  if (low.indexOf("fable") !== -1) return [8.0, 40.0, 0.2, 10.0, 16.0];
  if (low.indexOf("opus") !== -1) return [4.0, 20.0, 0.2, 5.0, 8.0];
  if (low.indexOf("sonnet") !== -1) return [2.0, 10.0, 0.1, 2.5, 4.0];
  if (low.indexOf("haiku") !== -1) return [0.1, 0.5, 0.01, 0.125, 0.2];
  return null;
}

function estimateCostUsd(
  modelName,
  inputTokens,
  outputTokens,
  cacheReadTokens,
  cacheCreationTokens,
  cacheCreation5m,
  cacheCreation1h
) {
  var rates = lookupPricing(modelName);
  if (!rates) return null;
  var inR = rates[0];
  var outR = rates[1];
  var crR = rates[2];
  var cw5R = rates[3];
  var cw1hR = rates[4];
  var cwCost;
  if (cacheCreation5m > 0 || cacheCreation1h > 0) {
    var remainder = Math.max(0, cacheCreationTokens - cacheCreation5m - cacheCreation1h);
    cwCost = ((cacheCreation5m + remainder) * cw5R + cacheCreation1h * cw1hR) / 1000000.0;
  } else {
    cwCost = (cacheCreationTokens * cw5R) / 1000000.0;
  }
  var total =
    (inputTokens * inR + outputTokens * outR + cacheReadTokens * crR) / 1000000.0 + cwCost;
  return roundN(total, 6);
}

function percentile(values, p) {
  if (!values || values.length === 0) return null;
  var ordered = values.slice().sort(function (a, b) {
    return a - b;
  });
  var idx = Math.max(
    0,
    Math.min(ordered.length - 1, Math.ceil((p / 100.0) * ordered.length) - 1)
  );
  return ordered[idx];
}

function emptyTokenBucket() {
  return {
    inputTokens: 0,
    outputTokens: 0,
    cacheReadInputTokens: 0,
    cacheCreationInputTokens: 0,
    cacheCreation5mInputTokens: 0,
    cacheCreation1hInputTokens: 0,
    thinkingTokens: 0,
    totalTokens: 0,
  };
}

function finalizeTokenBucket(b) {
  var total =
    b.inputTokens +
    b.outputTokens +
    b.cacheReadInputTokens +
    b.cacheCreationInputTokens;
  var denom = b.inputTokens + b.cacheReadInputTokens + b.cacheCreationInputTokens;
  var cacheHitRate = denom > 0 ? roundN(b.cacheReadInputTokens / denom, 4) : null;
  return {
    inputTokens: b.inputTokens,
    outputTokens: b.outputTokens,
    cacheReadInputTokens: b.cacheReadInputTokens,
    cacheCreationInputTokens: b.cacheCreationInputTokens,
    cacheCreation5mInputTokens: b.cacheCreation5mInputTokens,
    cacheCreation1hInputTokens: b.cacheCreation1hInputTokens,
    thinkingTokens: b.thinkingTokens,
    totalTokens: total,
    cacheHitRate: cacheHitRate,
  };
}

function aggregateToolCalls(calls) {
  var grouped = {};
  var durationsByTool = {};

  for (var i = 0; i < calls.length; i++) {
    var call = calls[i];
    var name = call.name;
    if (!grouped[name]) {
      grouped[name] = {
        calls: 0,
        errors: 0,
        incomplete: 0,
        totalDurationMs: 0,
        avgDurationMs: null,
        minDurationMs: null,
        p95DurationMs: null,
        maxDurationMs: null,
      };
      durationsByTool[name] = [];
    }
    var slot = grouped[name];
    slot.calls += 1;
    if (call.isError) slot.errors += 1;
    if (call.status === "incomplete") slot.incomplete += 1;
    var dur = call.durationMs;
    if (typeof dur === "number" && Number.isInteger(dur) && dur >= 0) {
      slot.totalDurationMs += dur;
      durationsByTool[name].push(dur);
    }
  }

  var names = Object.keys(grouped);
  for (var n = 0; n < names.length; n++) {
    var tname = names[n];
    var durs = durationsByTool[tname];
    if (durs.length > 0) {
      var sum = 0;
      var minVal = durs[0];
      var maxVal = durs[0];
      for (var d = 0; d < durs.length; d++) {
        sum += durs[d];
        if (durs[d] < minVal) minVal = durs[d];
        if (durs[d] > maxVal) maxVal = durs[d];
      }
      grouped[tname].avgDurationMs = roundN(sum / durs.length, 2);
      grouped[tname].minDurationMs = minVal;
      grouped[tname].p95DurationMs = percentile(durs, 95);
      grouped[tname].maxDurationMs = maxVal;
    }
  }

  names.sort(function (a, b) {
    var diff = grouped[b].calls - grouped[a].calls;
    return diff !== 0 ? diff : cmpStr(a, b);
  });

  var sortedObj = {};
  for (var s = 0; s < names.length; s++) {
    sortedObj[names[s]] = grouped[names[s]];
  }
  return sortedObj;
}

function parseJsonlTranscript(jsonlPath, desktopMeta, compact, maxOutputChars) {
  var sessionId = stemPath(jsonlPath);
  var cwd = desktopMeta ? desktopMeta.cwd || null : null;
  var entrypoint = null;
  var gitBranch = null;
  var claudeVersion = null;
  var aiTitle = null;

  var firstTs = null;
  var lastTs = null;

  var userMessages = 0;
  var turnsCount = 0;
  var activeTurnMs = 0;
  var thinkingDurationMs = 0;

  var prompts = [];
  var requests = {};
  var requestOrder = [];
  var syntheticReqCounter = 0;

  var toolCallsById = {};
  var toolCallOrder = [];

  var lastCostState = null;

  var rawContent = readTextFile(jsonlPath);
  if (rawContent === null) return null;

  var lines = rawContent.split(/\r?\n/);
  for (var i = 0; i < lines.length; i++) {
    var rawLine = lines[i].trim();
    if (!rawLine) continue;
    var obj;
    try {
      obj = JSON.parse(rawLine);
    } catch (e) {
      continue;
    }
    if (!isPlainObject(obj)) continue;

    var recType = obj.type;

    // Timestamps
    var ts = parseIsoTs(obj.timestamp);
    if (ts !== null) {
      if (firstTs === null || ts < firstTs) firstTs = ts;
      if (lastTs === null || ts > lastTs) lastTs = ts;
    }

    // Metadata fields
    if (!cwd && typeof obj.cwd === "string" && obj.cwd) cwd = obj.cwd;
    if (!entrypoint && typeof obj.entrypoint === "string" && obj.entrypoint) {
      entrypoint = obj.entrypoint;
    }
    if (!gitBranch && typeof obj.gitBranch === "string" && obj.gitBranch) {
      gitBranch = obj.gitBranch;
    }
    if (!claudeVersion && typeof obj.version === "string" && obj.version) {
      claudeVersion = obj.version;
    }
    if (recType === "ai-title" && typeof obj.aiTitle === "string") {
      aiTitle = obj.aiTitle;
    } else if (recType === "ai-title" && typeof obj.title === "string") {
      aiTitle = obj.title;
    }

    // Native cost-state event
    if (recType === "cost-state") {
      lastCostState = obj;
      continue;
    }

    // Turn duration events
    if (recType === "system" && obj.subtype === "turn_duration") {
      var dur = obj.durationMs;
      if (isFiniteNum(dur) && dur >= 0) {
        activeTurnMs += Math.trunc(dur);
        turnsCount += 1;
      }
      continue;
    }

    // Assistant records
    if (recType === "assistant") {
      var msg = obj.message;
      if (!isPlainObject(msg)) continue;

      var tdMs = obj.thinkingDurationMs;
      if (isFiniteNum(tdMs) && tdMs > 0) {
        thinkingDurationMs += Math.trunc(tdMs);
      }

      var model = msg.model || obj.requestedModel || null;
      var effort = obj.perTurnEffort || obj.effort || null;
      var usage = isPlainObject(msg.usage) ? msg.usage : null;
      var reqKey = obj.requestId || msg.id;
      if (typeof reqKey !== "string" || !reqKey) {
        syntheticReqCounter += 1;
        reqKey = "anon_" + syntheticReqCounter;
      }

      var content = msg.content;
      var chunkText = !compact ? extractTextFromContent(content) : "";

      if (usage !== null) {
        var cc = usage.cache_creation;
        var cc5 = isPlainObject(cc) ? cc.ephemeral_5m_input_tokens || 0 : 0;
        var cc1h = isPlainObject(cc) ? cc.ephemeral_1h_input_tokens || 0 : 0;

        var inTok = Math.trunc(Number(usage.input_tokens || 0));
        var outTok = Math.trunc(Number(usage.output_tokens || 0));
        var crTok = Math.trunc(Number(usage.cache_read_input_tokens || 0));
        var cwTok = Math.trunc(Number(usage.cache_creation_input_tokens || 0));

        var outDetails = usage.output_tokens_details;
        var thinkTok = 0;
        if (isPlainObject(outDetails)) {
          thinkTok = Math.trunc(
            Number(outDetails.thinking_tokens || outDetails.reasoning_tokens || 0)
          );
        }

        var prev = requests[reqKey];
        if (!prev) {
          requests[reqKey] = {
            requestId: reqKey,
            timestamp: epochMsToIso(ts),
            model: model || "unknown",
            effort: effort,
            thinkingDurationMs: isFiniteNum(tdMs) && tdMs > 0 ? Math.trunc(tdMs) : null,
            inputTokens: inTok,
            outputTokens: outTok,
            cacheReadInputTokens: crTok,
            cacheCreationInputTokens: cwTok,
            cacheCreation5mInputTokens: Math.trunc(Number(cc5 || 0)),
            cacheCreation1hInputTokens: Math.trunc(Number(cc1h || 0)),
            thinkingTokens: thinkTok,
            _textParts: chunkText ? [chunkText] : [],
            toolUseIds: [],
          };
          requestOrder.push(reqKey);
        } else {
          if (outTok >= prev.outputTokens) {
            prev.inputTokens = inTok;
            prev.outputTokens = outTok;
            prev.cacheReadInputTokens = crTok;
            prev.cacheCreationInputTokens = cwTok;
            prev.cacheCreation5mInputTokens = Math.trunc(Number(cc5 || 0));
            prev.cacheCreation1hInputTokens = Math.trunc(Number(cc1h || 0));
            prev.thinkingTokens = Math.max(prev.thinkingTokens, thinkTok);
          }
          if (!prev.effort && effort) prev.effort = effort;
          if (prev.model === "unknown" && model) prev.model = model;
          if (isFiniteNum(tdMs) && tdMs > 0) {
            prev.thinkingDurationMs = (prev.thinkingDurationMs || 0) + Math.trunc(tdMs);
          }
          if (chunkText && prev._textParts.indexOf(chunkText) === -1) {
            prev._textParts.push(chunkText);
          }
        }
      }

      if (Array.isArray(content)) {
        for (var b = 0; b < content.length; b++) {
          var block = content[b];
          if (isPlainObject(block) && block.type === "tool_use") {
            var tid = block.id;
            var tname = block.name || "unknown";
            if (typeof tid === "string" && tid && !toolCallsById[tid]) {
              var callEntry = {
                toolUseId: tid,
                requestId: reqKey,
                name: tname,
                startedAt: epochMsToIso(ts),
                _startMs: ts,
                endedAt: null,
                durationMs: null,
                isError: false,
                status: "incomplete",
              };
              if (!compact) {
                callEntry.input =
                  block.input !== undefined ? sanitizeValue(block.input) : null;
                callEntry.output = null;
                callEntry.outputTruncated = false;
              }
              toolCallsById[tid] = callEntry;
              toolCallOrder.push(tid);
              if (requests[reqKey] && requests[reqKey].toolUseIds.indexOf(tid) === -1) {
                requests[reqKey].toolUseIds.push(tid);
              }
            }
          }
        }
      }
      continue;
    }

    // User records
    if (recType === "user") {
      var umsg = obj.message;
      if (!isPlainObject(umsg)) continue;
      var ucontent = umsg.content;
      var hasToolResult = false;

      if (Array.isArray(ucontent)) {
        var tur = obj.toolUseResult;
        var turDur = null;
        if (isPlainObject(tur)) {
          var rawD =
            tur.durationMs !== undefined && tur.durationMs !== null
              ? tur.durationMs
              : tur.totalDurationMs;
          if (isFiniteNum(rawD) && rawD >= 0) {
            turDur = Math.trunc(rawD);
          }
        }

        for (var ub = 0; ub < ucontent.length; ub++) {
          var ublock = ucontent[ub];
          if (isPlainObject(ublock) && ublock.type === "tool_result") {
            hasToolResult = true;
            var utid = ublock.tool_use_id;
            if (typeof utid === "string" && toolCallsById[utid]) {
              var call = toolCallsById[utid];
              call.endedAt = epochMsToIso(ts);
              call.isError = Boolean(ublock.is_error);
              call.status = call.isError ? "error" : "ok";
              if (call._startMs !== null && ts !== null) {
                var deltaMs = Math.round(ts - call._startMs);
                if (deltaMs >= 0) call.durationMs = deltaMs;
              }
              if (call.durationMs === null && turDur !== null) {
                call.durationMs = turDur;
              }
              if (!compact) {
                var rawOut = extractTextFromContent(ublock.content);
                var truncRes = truncateText(rawOut, maxOutputChars);
                call.output = truncRes[0];
                call.outputTruncated = truncRes[1];
              }
            }
          }
        }
      }

      if (!hasToolResult && !obj.isMeta) {
        userMessages += 1;
        if (!compact) {
          var promptText = extractTextFromContent(ucontent);
          if (promptText) {
            prompts.push({
              index: userMessages,
              uuid: obj.uuid !== undefined ? obj.uuid : null,
              timestamp: epochMsToIso(ts),
              text: promptText,
            });
          }
        }
      }
    }
  }

  // Ignore completely empty/stub transcripts with no activity
  if (
    requestOrder.length === 0 &&
    toolCallOrder.length === 0 &&
    lastCostState === null &&
    userMessages === 0
  ) {
    return null;
  }

  // Aggregate tokens, models, and effort from deduplicated requests
  var tokensTotal = emptyTokenBucket();
  var byModel = {};
  var byEffort = {};
  var desktopEffort = desktopMeta ? desktopMeta.effort || null : null;

  for (var r = 0; r < requestOrder.length; r++) {
    var req = requests[requestOrder[r]];
    var m = req.model || "unknown";
    var eff = req.effort || desktopEffort || "unspecified";

    for (var tk = 0; tk < TOKEN_KEYS.length; tk++) {
      var k = TOKEN_KEYS[tk];
      tokensTotal[k] += req[k];
    }

    if (!byModel[m]) {
      byModel[m] = {
        requests: 0,
        tokens: emptyTokenBucket(),
        costUSD: null,
        costSource: "estimated",
      };
    }
    byModel[m].requests += 1;
    for (var mk = 0; mk < TOKEN_KEYS.length; mk++) {
      var keyM = TOKEN_KEYS[mk];
      byModel[m].tokens[keyM] += req[keyM];
    }

    if (!byEffort[eff]) {
      byEffort[eff] = {
        requests: 0,
        tokens: emptyTokenBucket(),
      };
    }
    byEffort[eff].requests += 1;
    for (var ek = 0; ek < TOKEN_KEYS.length; ek++) {
      var keyE = TOKEN_KEYS[ek];
      byEffort[eff].tokens[keyE] += req[keyE];
    }
  }

  // Reconcile native cost-state (if present) vs estimated cost
  var costSource = "estimated";
  var totalCostUsd = null;
  var costByModel = {};

  if (lastCostState && isFiniteNum(lastCostState.totalCostUSD)) {
    costSource = "native";
    totalCostUsd = roundN(lastCostState.totalCostUSD, 6);
    var nativeMu = lastCostState.modelUsage;
    if (isPlainObject(nativeMu)) {
      var nativeThinkingSum = 0;
      var muKeys = Object.keys(nativeMu);
      for (var mi = 0; mi < muKeys.length; mi++) {
        var mName = muKeys[mi];
        var mData = nativeMu[mName];
        if (!isPlainObject(mData)) continue;
        var mCost = mData.costUSD;
        if (isFiniteNum(mCost)) {
          var roundedMCost = roundN(mCost, 6);
          costByModel[mName] = { costUSD: roundedMCost, source: "native" };
          if (byModel[mName]) {
            byModel[mName].costUSD = roundedMCost;
            byModel[mName].costSource = "native";
          }
        }
        var tTok = Math.trunc(Number(mData.thinkingTokens || 0));
        nativeThinkingSum += tTok;
        if (byModel[mName] && tTok > byModel[mName].tokens.thinkingTokens) {
          byModel[mName].tokens.thinkingTokens = tTok;
        }
      }
      if (nativeThinkingSum > tokensTotal.thinkingTokens) {
        tokensTotal.thinkingTokens = nativeThinkingSum;
      }
    }
  } else {
    var estSum = 0.0;
    var anyEst = false;
    var bmKeys = Object.keys(byModel);
    for (var bi = 0; bi < bmKeys.length; bi++) {
      var bmName = bmKeys[bi];
      var mslot = byModel[bmName];
      var tb = mslot.tokens;
      var est = estimateCostUsd(
        bmName,
        tb.inputTokens,
        tb.outputTokens,
        tb.cacheReadInputTokens,
        tb.cacheCreationInputTokens,
        tb.cacheCreation5mInputTokens,
        tb.cacheCreation1hInputTokens
      );
      mslot.costUSD = est;
      mslot.costSource = est !== null ? "estimated" : "unknown";
      if (est !== null) {
        estSum += est;
        anyEst = true;
        costByModel[bmName] = { costUSD: est, source: "estimated" };
      }
    }
    if (anyEst) {
      totalCostUsd = roundN(estSum, 6);
    } else {
      costSource = "unknown";
    }
  }

  // Finalize token buckets
  var tokensSummary = finalizeTokenBucket(tokensTotal);
  var modelNames = Object.keys(byModel);
  for (var fmIdx = 0; fmIdx < modelNames.length; fmIdx++) {
    byModel[modelNames[fmIdx]].tokens = finalizeTokenBucket(
      byModel[modelNames[fmIdx]].tokens
    );
  }
  var effortNames = Object.keys(byEffort);
  for (var feIdx = 0; feIdx < effortNames.length; feIdx++) {
    byEffort[effortNames[feIdx]].tokens = finalizeTokenBucket(
      byEffort[effortNames[feIdx]].tokens
    );
  }

  // Clean internal keys from tool calls
  var callsClean = [];
  var measuredToolMs = 0;
  var toolErrorsCount = 0;
  for (var ci = 0; ci < toolCallOrder.length; ci++) {
    var orig = toolCallsById[toolCallOrder[ci]];
    var cleaned = {
      toolUseId: orig.toolUseId,
      requestId: orig.requestId,
      name: orig.name,
      startedAt: orig.startedAt,
      endedAt: orig.endedAt,
      durationMs: orig.durationMs,
      isError: orig.isError,
      status: orig.status,
    };
    if (!compact) {
      cleaned.input = orig.input;
      cleaned.output = orig.output;
      cleaned.outputTruncated = orig.outputTruncated;
    }
    if (typeof cleaned.durationMs === "number" && Number.isInteger(cleaned.durationMs)) {
      measuredToolMs += cleaned.durationMs;
    }
    if (cleaned.isError) toolErrorsCount += 1;
    callsClean.push(cleaned);
  }

  var byTool = aggregateToolCalls(callsClean);

  // Durations
  var startedIso =
    (desktopMeta && desktopMeta.createdAt) || epochMsToIso(firstTs);
  var endedIso =
    epochMsToIso(lastTs) || (desktopMeta && desktopMeta.lastActivityAt) || null;

  var wallClockMs = null;
  if (lastCostState && isFiniteNum(lastCostState.totalDuration)) {
    wallClockMs = Math.trunc(lastCostState.totalDuration);
  } else if (firstTs !== null && lastTs !== null) {
    wallClockMs = Math.max(0, Math.round(lastTs - firstTs));
  } else if (desktopMeta && desktopMeta.createdAtMs && desktopMeta.lastActivityAtMs) {
    wallClockMs = Math.max(
      0,
      Math.trunc(desktopMeta.lastActivityAtMs - desktopMeta.createdAtMs)
    );
  }

  var apiDurationMs = null;
  if (lastCostState && isFiniteNum(lastCostState.totalAPIDuration)) {
    apiDurationMs = Math.trunc(lastCostState.totalAPIDuration);
  }

  var toolDurationMs = measuredToolMs;
  if (lastCostState && isFiniteNum(lastCostState.totalToolDuration)) {
    toolDurationMs = Math.trunc(lastCostState.totalToolDuration);
  }

  // Primary model & sorted lists
  var modelsSorted = modelNames.slice().sort(function (a, b) {
    var diff = byModel[b].requests - byModel[a].requests;
    return diff !== 0 ? diff : cmpStr(a, b);
  });
  var primaryModel =
    modelsSorted.length > 0
      ? modelsSorted[0]
      : desktopMeta
      ? desktopMeta.model || null
      : null;

  var effortsSorted = effortNames.slice().sort(function (a, b) {
    var diff = byEffort[b].requests - byEffort[a].requests;
    return diff !== 0 ? diff : cmpStr(a, b);
  });
  var resolvedEntrypoint = entrypoint || (desktopMeta ? "claude-desktop" : "unknown");

  var requestsDetail = [];
  if (!compact) {
    for (var rd = 0; rd < requestOrder.length; rd++) {
      var rObj = requests[requestOrder[rd]];
      var rawResp = (rObj._textParts || []).join("\n").trim();
      var respTruncRes = truncateText(rawResp, maxOutputChars);
      var reqTokens = finalizeTokenBucket({
        inputTokens: rObj.inputTokens,
        outputTokens: rObj.outputTokens,
        cacheReadInputTokens: rObj.cacheReadInputTokens,
        cacheCreationInputTokens: rObj.cacheCreationInputTokens,
        cacheCreation5mInputTokens: rObj.cacheCreation5mInputTokens,
        cacheCreation1hInputTokens: rObj.cacheCreation1hInputTokens,
        thinkingTokens: rObj.thinkingTokens,
        totalTokens: 0,
      });
      requestsDetail.push({
        requestId: rObj.requestId,
        timestamp: rObj.timestamp,
        model: rObj.model,
        effort: rObj.effort || desktopEffort || "unspecified",
        thinkingDurationMs: rObj.thinkingDurationMs,
        tokens: reqTokens,
        toolUseIds: rObj.toolUseIds,
        responseText: respTruncRes[0] ? respTruncRes[0] : null,
        responseTruncated: respTruncRes[1],
      });
    }
  }

  var toolsObj = { summary: byTool };
  if (!compact) {
    toolsObj.calls = callsClean;
  }

  var sessionObj = {
    sessionId: sessionId,
    desktopSessionId: desktopMeta ? desktopMeta.desktopSessionId || null : null,
    title: (desktopMeta && desktopMeta.title) || aiTitle || null,
    cwd: cwd,
    projectName: cwd ? basenamePath(cwd) : null,
    entrypoint: resolvedEntrypoint,
    isDesktop: resolvedEntrypoint === "claude-desktop" || desktopMeta !== null,
    permissionMode: desktopMeta ? desktopMeta.permissionMode || null : null,
    isArchived: desktopMeta ? Boolean(desktopMeta.isArchived) : false,
    gitBranch: gitBranch,
    claudeCodeVersion: claudeVersion,
    startedAt: startedIso,
    endedAt: endedIso,
    activity: {
      userMessages: userMessages,
      assistantRequests: requestOrder.length,
      turns: turnsCount,
      toolCalls: callsClean.length,
      toolErrors: toolErrorsCount,
    },
    duration: {
      wallClockMs: wallClockMs,
      activeTurnMs: activeTurnMs > 0 ? activeTurnMs : null,
      apiDurationMs: apiDurationMs,
      toolDurationMs: toolDurationMs,
      measuredToolDurationMs: measuredToolMs,
      thinkingDurationMs: thinkingDurationMs > 0 ? thinkingDurationMs : null,
    },
    primaryModel: primaryModel,
    modelsUsed: modelsSorted,
    desktopEffort: desktopEffort,
    effortsUsed: effortsSorted,
    tokens: tokensSummary,
    cost: {
      totalUSD: totalCostUsd,
      source: costSource,
      byModel: costByModel,
    },
    byModel: byModel,
    byEffort: byEffort,
    tools: toolsObj,
  };

  if (!compact) {
    sessionObj.prompts = prompts;
    sessionObj.requests = requestsDetail;
  }

  return sessionObj;
}

function parseSubagents(mainJsonlPath, compact, maxOutputChars) {
  var subDir = joinPath(joinPath(dirnamePath(mainJsonlPath), stemPath(mainJsonlPath)), "subagents");
  if (!isDir(subDir)) return [];
  var files = listDir(subDir)
    .filter(function (f) {
      return f.slice(-6) === ".jsonl";
    })
    .sort(cmpStr);

  var subagents = [];
  for (var i = 0; i < files.length; i++) {
    var subPath = joinPath(subDir, files[i]);
    var parsed = parseJsonlTranscript(subPath, null, compact, maxOutputChars);
    if (!parsed) continue;
    var subEntry = {
      subagentId: stemPath(subPath),
      startedAt: parsed.startedAt,
      endedAt: parsed.endedAt,
      primaryModel: parsed.primaryModel,
      modelsUsed: parsed.modelsUsed,
      effortsUsed: parsed.effortsUsed,
      activity: parsed.activity,
      duration: parsed.duration,
      tokens: parsed.tokens,
      cost: parsed.cost,
      tools: parsed.tools,
    };
    if (!compact) {
      subEntry.prompts = parsed.prompts || [];
      subEntry.requests = parsed.requests || [];
    }
    subagents.push(subEntry);
  }
  return subagents;
}

function buildGlobalSummary(sessions) {
  var tokensTotal = emptyTokenBucket();
  var byModel = {};
  var byEffort = {};
  var byEntrypoint = {};
  var byProject = {};
  var allToolCalls = [];
  var toolAggFallback = {};

  var totalCostUsd = 0.0;
  var nativeCostSessions = 0;
  var estimatedCostSessions = 0;
  var unknownCostSessions = 0;

  var totalWallMs = 0;
  var totalActiveMs = 0;
  var totalApiMs = 0;
  var totalToolMs = 0;
  var totalThinkingMs = 0;
  var totalRequests = 0;
  var totalUserMsgs = 0;
  var totalTurns = 0;
  var totalSubagents = 0;
  var desktopSessionsCount = 0;

  var earliest = null;
  var latest = null;

  for (var i = 0; i < sessions.length; i++) {
    var s = sessions[i];
    var ep = s.entrypoint || "unknown";
    byEntrypoint[ep] = (byEntrypoint[ep] || 0) + 1;
    if (s.isDesktop) desktopSessionsCount += 1;

    totalRequests += s.activity.assistantRequests;
    totalUserMsgs += s.activity.userMessages;
    totalTurns += s.activity.turns;
    totalSubagents += s.subagentsCount || 0;

    var st = s.startedAt;
    var en = s.endedAt;
    if (st && (earliest === null || st < earliest)) earliest = st;
    if (en && (latest === null || en > latest)) latest = en;

    var d = s.duration;
    if (typeof d.wallClockMs === "number" && Number.isInteger(d.wallClockMs)) {
      totalWallMs += d.wallClockMs;
    }
    if (typeof d.activeTurnMs === "number" && Number.isInteger(d.activeTurnMs)) {
      totalActiveMs += d.activeTurnMs;
    }
    if (typeof d.apiDurationMs === "number" && Number.isInteger(d.apiDurationMs)) {
      totalApiMs += d.apiDurationMs;
    }
    if (typeof d.toolDurationMs === "number" && Number.isInteger(d.toolDurationMs)) {
      totalToolMs += d.toolDurationMs;
    }
    if (typeof d.thinkingDurationMs === "number" && Number.isInteger(d.thinkingDurationMs)) {
      totalThinkingMs += d.thinkingDurationMs;
    }

    // Tokens
    var tb = s.tokens;
    for (var tk = 0; tk < TOKEN_KEYS.length; tk++) {
      var k = TOKEN_KEYS[tk];
      tokensTotal[k] += tb[k] || 0;
    }

    // Costs
    var cSrc = s.cost.source;
    var cVal = s.cost.totalUSD;
    if (cSrc === "native") nativeCostSessions += 1;
    else if (cSrc === "estimated") estimatedCostSessions += 1;
    else unknownCostSessions += 1;
    if (isFiniteNum(cVal)) totalCostUsd += cVal;

    // By project
    var projKey = s.cwd || "unknown";
    if (!byProject[projKey]) {
      byProject[projKey] = {
        projectName: s.projectName || "unknown",
        sessions: 0,
        costUSD: 0.0,
        totalTokens: 0,
        toolCalls: 0,
      };
    }
    var pslot = byProject[projKey];
    pslot.sessions += 1;
    pslot.costUSD = roundN(pslot.costUSD + (isFiniteNum(cVal) ? cVal : 0.0), 6);
    pslot.totalTokens += tb.totalTokens || 0;
    pslot.toolCalls += s.activity.toolCalls;

    // By model
    var smKeys = Object.keys(s.byModel);
    for (var mi = 0; mi < smKeys.length; mi++) {
      var mName = smKeys[mi];
      var mdata = s.byModel[mName];
      if (!byModel[mName]) {
        byModel[mName] = {
          sessions: 0,
          requests: 0,
          tokens: emptyTokenBucket(),
          costUSD: 0.0,
        };
      }
      var mslot = byModel[mName];
      mslot.sessions += 1;
      mslot.requests += mdata.requests;
      for (var mk = 0; mk < TOKEN_KEYS.length; mk++) {
        var keyM = TOKEN_KEYS[mk];
        mslot.tokens[keyM] += mdata.tokens[keyM] || 0;
      }
      if (isFiniteNum(mdata.costUSD)) {
        mslot.costUSD = roundN(mslot.costUSD + mdata.costUSD, 6);
      }
    }

    // By effort
    var seKeys = Object.keys(s.byEffort);
    for (var ei = 0; ei < seKeys.length; ei++) {
      var eName = seKeys[ei];
      var edata = s.byEffort[eName];
      if (!byEffort[eName]) {
        byEffort[eName] = {
          sessions: 0,
          requests: 0,
          tokens: emptyTokenBucket(),
        };
      }
      var eslot = byEffort[eName];
      eslot.sessions += 1;
      eslot.requests += edata.requests;
      for (var ek = 0; ek < TOKEN_KEYS.length; ek++) {
        var keyE = TOKEN_KEYS[ek];
        eslot.tokens[keyE] += edata.tokens[keyE] || 0;
      }
    }

    // Tools
    var calls = s.tools.calls;
    if (Array.isArray(calls)) {
      for (var ci = 0; ci < calls.length; ci++) {
        allToolCalls.push(calls[ci]);
      }
    } else {
      var tsKeys = Object.keys(s.tools.summary);
      for (var ti = 0; ti < tsKeys.length; ti++) {
        var tname = tsKeys[ti];
        var tdata = s.tools.summary[tname];
        if (!toolAggFallback[tname]) {
          toolAggFallback[tname] = {
            calls: 0,
            errors: 0,
            incomplete: 0,
            totalDurationMs: 0,
          };
        }
        toolAggFallback[tname].calls += tdata.calls;
        toolAggFallback[tname].errors += tdata.errors;
        toolAggFallback[tname].incomplete += tdata.incomplete;
        toolAggFallback[tname].totalDurationMs += tdata.totalDurationMs;
      }
    }
  }

  var mKeys = Object.keys(byModel);
  for (var mfi = 0; mfi < mKeys.length; mfi++) {
    byModel[mKeys[mfi]].tokens = finalizeTokenBucket(byModel[mKeys[mfi]].tokens);
  }
  var eKeys = Object.keys(byEffort);
  for (var efi = 0; efi < eKeys.length; efi++) {
    byEffort[eKeys[efi]].tokens = finalizeTokenBucket(byEffort[eKeys[efi]].tokens);
  }

  var byTool;
  if (allToolCalls.length > 0) {
    byTool = aggregateToolCalls(allToolCalls);
  } else {
    var tfKeys = Object.keys(toolAggFallback);
    for (var tfi = 0; tfi < tfKeys.length; tfi++) {
      var slot = toolAggFallback[tfKeys[tfi]];
      var completed = slot.calls - slot.incomplete;
      slot.avgDurationMs =
        completed > 0 ? roundN(slot.totalDurationMs / completed, 2) : null;
    }
    tfKeys.sort(function (a, b) {
      var diff = toolAggFallback[b].calls - toolAggFallback[a].calls;
      return diff !== 0 ? diff : cmpStr(a, b);
    });
    byTool = {};
    for (var tfs = 0; tfs < tfKeys.length; tfs++) {
      byTool[tfKeys[tfs]] = toolAggFallback[tfKeys[tfs]];
    }
  }

  var totalToolCalls = 0;
  var totalToolErrors = 0;
  var btKeys = Object.keys(byTool);
  for (var bti = 0; bti < btKeys.length; bti++) {
    totalToolCalls += byTool[btKeys[bti]].calls;
    totalToolErrors += byTool[btKeys[bti]].errors;
  }

  var sortedEntrypoint = {};
  Object.keys(byEntrypoint)
    .sort(cmpStr)
    .forEach(function (k) {
      sortedEntrypoint[k] = byEntrypoint[k];
    });

  var sortedModel = {};
  mKeys
    .slice()
    .sort(function (a, b) {
      var diff = byModel[b].requests - byModel[a].requests;
      return diff !== 0 ? diff : cmpStr(a, b);
    })
    .forEach(function (k) {
      sortedModel[k] = byModel[k];
    });

  var sortedEffort = {};
  eKeys
    .slice()
    .sort(function (a, b) {
      var diff = byEffort[b].requests - byEffort[a].requests;
      return diff !== 0 ? diff : cmpStr(a, b);
    })
    .forEach(function (k) {
      sortedEffort[k] = byEffort[k];
    });

  var sortedProject = {};
  Object.keys(byProject)
    .sort(function (a, b) {
      var diff = byProject[b].sessions - byProject[a].sessions;
      return diff !== 0 ? diff : cmpStr(a, b);
    })
    .forEach(function (k) {
      sortedProject[k] = byProject[k];
    });

  return {
    sessionsCount: sessions.length,
    desktopSessionsCount: desktopSessionsCount,
    subagentsCount: totalSubagents,
    dateRange: {
      earliest: earliest,
      latest: latest,
    },
    activity: {
      userMessages: totalUserMsgs,
      assistantRequests: totalRequests,
      turns: totalTurns,
      toolCalls: totalToolCalls,
      toolErrors: totalToolErrors,
    },
    duration: {
      totalWallClockMs: totalWallMs,
      totalActiveTurnMs: totalActiveMs,
      totalApiDurationMs: totalApiMs,
      totalToolDurationMs: totalToolMs,
      totalThinkingDurationMs: totalThinkingMs,
    },
    tokens: finalizeTokenBucket(tokensTotal),
    cost: {
      totalUSD: roundN(totalCostUsd, 6),
      nativeSessions: nativeCostSessions,
      estimatedSessions: estimatedCostSessions,
      unknownSessions: unknownCostSessions,
    },
    byEntrypoint: sortedEntrypoint,
    byModel: sortedModel,
    byEffort: sortedEffort,
    byTool: byTool,
    byProject: sortedProject,
  };
}

function collectSessions(
  scope,
  projectDir,
  sinceMs,
  untilMs,
  entrypointFilter,
  includeSubagents,
  compact,
  sessionIdOverride,
  maxOutputChars
) {
  var configDir = getClaudeConfigDir();
  var projectsDir = joinPath(configDir, "projects");
  var desktopIndex = loadDesktopSessionsIndex();
  var projectNorm = normalizePath(projectDir) || "";

  var jsonlFiles = [];
  if (isDir(projectsDir)) {
    var projSubdirs = listDir(projectsDir);
    for (var i = 0; i < projSubdirs.length; i++) {
      var subPath = joinPath(projectsDir, projSubdirs[i]);
      if (!isDir(subPath)) continue;
      var entries = listDir(subPath);
      for (var j = 0; j < entries.length; j++) {
        if (entries[j].slice(-6) === ".jsonl") {
          jsonlFiles.push(joinPath(subPath, entries[j]));
        }
      }
    }
    jsonlFiles.sort(cmpStr);
  }

  if (scope === "session") {
    var targetSid = sessionIdOverride || getEnv("CLAUDE_SESSION_ID");
    if (targetSid) {
      jsonlFiles = jsonlFiles.filter(function (p) {
        return stemPath(p) === targetSid;
      });
    } else {
      var ordered = jsonlFiles.slice().sort(function (a, b) {
        return getMtimeMs(b) - getMtimeMs(a);
      });
      var chosen = null;
      for (var oi = 0; oi < ordered.length; oi++) {
        var cand = ordered[oi];
        var dm = desktopIndex[stemPath(cand)];
        if (dm && pathMatchesProject(dm.cwd, projectNorm)) {
          chosen = cand;
          break;
        }
        var rawHead = readTextFile(cand);
        if (rawHead) {
          var headLines = rawHead.split(/\r?\n/);
          var limit = Math.min(headLines.length, 26);
          for (var hl = 0; hl < limit; hl++) {
            var lineStr = headLines[hl].trim();
            if (!lineStr) continue;
            try {
              var rec = JSON.parse(lineStr);
              if (isPlainObject(rec) && pathMatchesProject(rec.cwd, projectNorm)) {
                chosen = cand;
                break;
              }
            } catch (e) {
              continue;
            }
          }
        }
        if (chosen !== null) break;
      }
      if (chosen === null && ordered.length > 0) {
        chosen = ordered[0];
      }
      jsonlFiles = chosen ? [chosen] : [];
    }
  }

  var sessions = [];
  for (var fi = 0; fi < jsonlFiles.length; fi++) {
    var jpath = jsonlFiles[fi];
    var sid = stemPath(jpath);
    var desktopMeta = desktopIndex[sid] || null;

    if (scope === "project" && desktopMeta && desktopMeta.cwd) {
      if (!pathMatchesProject(desktopMeta.cwd, projectNorm)) continue;
    }

    var parsed = parseJsonlTranscript(jpath, desktopMeta, compact, maxOutputChars);
    if (!parsed) continue;

    if (scope === "project") {
      if (!pathMatchesProject(parsed.cwd, projectNorm)) continue;
    }

    if (entrypointFilter !== "all") {
      if (entrypointFilter === "claude-desktop") {
        if (!parsed.isDesktop) continue;
      } else if (parsed.entrypoint !== entrypointFilter) {
        continue;
      }
    }

    var refMs = parseIsoTs(parsed.endedAt);
    if (refMs === null) refMs = parseIsoTs(parsed.startedAt);
    if (sinceMs !== null && (refMs === null || refMs < sinceMs)) continue;
    if (untilMs !== null && (refMs === null || refMs > untilMs)) continue;

    if (includeSubagents) {
      var subs = parseSubagents(jpath, compact, maxOutputChars);
      parsed.subagentsCount = subs.length;
      parsed.subagents = subs;
    } else {
      parsed.subagentsCount = 0;
      parsed.subagents = [];
    }

    sessions.push(parsed);
  }

  // Sort newest first
  sessions.sort(function (a, b) {
    var ka = a.endedAt || a.startedAt || "";
    var kb = b.endedAt || b.startedAt || "";
    return cmpStr(kb, ka);
  });

  var diagnostics = {
    claudeProjectsDir: projectsDir,
    claudeDesktopSessionsDirs: getClaudeDesktopSessionsDirs(),
    desktopMetadataFilesIndexed: Object.keys(desktopIndex).length,
    transcriptFilesScanned: jsonlFiles.length,
  };
  return [sessions, diagnostics];
}

function printUsage() {
  var help =
    "Usage: osascript -l JavaScript extract_usage.js [options]\n\n" +
    "Options:\n" +
    "  --scope <all|project|session>        Scope (default: all)\n" +
    "  --session-id <id>                    Explicit session UUID when --scope=session\n" +
    "  --project-dir <path>                 Project root directory (default: .)\n" +
    "  --since <YYYY-MM-DD|ISO-8601>        Lower date bound\n" +
    "  --until <YYYY-MM-DD|ISO-8601>        Upper date bound\n" +
    "  --entrypoint <all|claude-desktop|cli|sdk-ts>\n" +
    "                                       Filter by entrypoint (default: all)\n" +
    "  --no-subagents                       Exclude subagent transcripts\n" +
    "  --compact                            Omit prompts, responses, requests, and tool calls\n" +
    "  --max-output-chars <int>             Max chars per tool output/response (default: 4000)\n" +
    "  --out <path>                         Output JSON file path\n" +
    "  --print-summary                      Print compact JSON summary to stdout\n" +
    "  -h, --help                           Show this help message\n";
  writeStdout(help);
}

function parseArgs(argv) {
  var args = {
    scope: "all",
    sessionId: null,
    projectDir: ".",
    since: null,
    until: null,
    entrypoint: "all",
    noSubagents: false,
    compact: false,
    maxOutputChars: 4000,
    out: null,
    printSummary: false,
    help: false,
  };

  function requireValue(flag, idx) {
    if (idx + 1 >= argv.length) {
      throw new Error("Option " + flag + " requires a value.");
    }
    return argv[idx + 1];
  }

  for (var i = 0; i < argv.length; i++) {
    var token = argv[i];
    var flag = token;
    var inlineVal = null;
    var eqIdx = token.indexOf("=");
    if (token.indexOf("--") === 0 && eqIdx !== -1) {
      flag = token.slice(0, eqIdx);
      inlineVal = token.slice(eqIdx + 1);
    }

    var val;
    switch (flag) {
      case "-h":
      case "--help":
        args.help = true;
        break;
      case "--scope":
        val = inlineVal !== null ? inlineVal : requireValue(flag, i++);
        if (val !== "all" && val !== "project" && val !== "session") {
          throw new Error("Invalid --scope '" + val + "'. Choose from: all, project, session.");
        }
        args.scope = val;
        break;
      case "--session-id":
        args.sessionId = inlineVal !== null ? inlineVal : requireValue(flag, i++);
        break;
      case "--project-dir":
        args.projectDir = inlineVal !== null ? inlineVal : requireValue(flag, i++);
        break;
      case "--since":
        args.since = inlineVal !== null ? inlineVal : requireValue(flag, i++);
        break;
      case "--until":
        args.until = inlineVal !== null ? inlineVal : requireValue(flag, i++);
        break;
      case "--entrypoint":
        val = inlineVal !== null ? inlineVal : requireValue(flag, i++);
        if (
          val !== "all" &&
          val !== "claude-desktop" &&
          val !== "cli" &&
          val !== "sdk-ts"
        ) {
          throw new Error(
            "Invalid --entrypoint '" + val + "'. Choose from: all, claude-desktop, cli, sdk-ts."
          );
        }
        args.entrypoint = val;
        break;
      case "--no-subagents":
        args.noSubagents = true;
        break;
      case "--compact":
        args.compact = true;
        break;
      case "--max-output-chars":
        val = inlineVal !== null ? inlineVal : requireValue(flag, i++);
        if (!/^-?\d+$/.test(val)) {
          throw new Error("Invalid --max-output-chars '" + val + "'. Must be an integer.");
        }
        args.maxOutputChars = parseInt(val, 10);
        break;
      case "--out":
        args.out = inlineVal !== null ? inlineVal : requireValue(flag, i++);
        break;
      case "--print-summary":
        args.printSummary = true;
        break;
      default:
        throw new Error("Unrecognized argument: " + token);
    }
  }
  return args;
}

function formatUtcStamp(dateObj) {
  return (
    dateObj.getUTCFullYear() +
    pad2(dateObj.getUTCMonth() + 1) +
    pad2(dateObj.getUTCDate()) +
    "-" +
    pad2(dateObj.getUTCHours()) +
    pad2(dateObj.getUTCMinutes()) +
    pad2(dateObj.getUTCSeconds())
  );
}

function run(argv) {
  try {
    var args = parseArgs(argv || []);
    if (args.help) {
      printUsage();
      $.exit(0);
    }

    var projectDir = resolveRealPath(args.projectDir);
    var sinceMs = parseDateFilter(args.since, false);
    var untilMs = parseDateFilter(args.until, true);

    var collected = collectSessions(
      args.scope,
      projectDir,
      sinceMs,
      untilMs,
      args.entrypoint,
      !args.noSubagents,
      args.compact,
      args.sessionId,
      args.maxOutputChars
    );
    var sessions = collected[0];
    var diagnostics = collected[1];

    var now = new Date();
    var summary = buildGlobalSummary(sessions);

    var pricingMap = {};
    var pKeys = Object.keys(MODEL_PRICING_PER_M);
    for (var pi = 0; pi < pKeys.length; pi++) {
      var pk = pKeys[pi];
      var pv = MODEL_PRICING_PER_M[pk];
      pricingMap[pk] = {
        input: pv[0],
        output: pv[1],
        cacheRead: pv[2],
        cacheWrite5m: pv[3],
        cacheWrite1h: pv[4],
      };
    }

    var report = {
      schemaVersion: SCHEMA_VERSION,
      generatedAt: epochMsToIso(now.getTime()),
      scope: args.scope,
      projectDir: args.scope === "project" || args.scope === "session" ? projectDir : null,
      filters: {
        since: args.since,
        until: args.until,
        entrypoint: args.entrypoint,
        includeSubagents: !args.noSubagents,
        compact: args.compact,
        maxOutputChars: args.maxOutputChars,
      },
      environment: {
        os: "Darwin",
        osRelease: getOsRelease(),
        engine: "jxa",
        pythonVersion: null,
      },
      pricingAssumptionsUSDPerMillion: pricingMap,
      sources: diagnostics,
      summary: summary,
      sessions: sessions,
    };

    var outPath;
    if (args.out) {
      outPath = expandUser(args.out);
    } else {
      var stamp = formatUtcStamp(now);
      outPath = joinPath(
        joinPath(projectDir, "usage-reports"),
        "decodex-usage-" + args.scope + "-" + stamp + ".json"
      );
    }

    writeTextFile(outPath, JSON.stringify(report, null, 2) + "\n");

    if (args.printSummary) {
      var topToolKeys = Object.keys(summary.byTool).slice(0, 8);
      var topTools = [];
      for (var ti = 0; ti < topToolKeys.length; ti++) {
        var tk = topToolKeys[ti];
        topTools.push({
          tool: tk,
          calls: summary.byTool[tk].calls,
          avgDurationMs: summary.byTool[tk].avgDurationMs,
        });
      }

      var compactOut = {
        outputFile: outPath,
        scope: args.scope,
        sessionsCount: summary.sessionsCount,
        desktopSessionsCount: summary.desktopSessionsCount,
        subagentsCount: summary.subagentsCount,
        dateRange: summary.dateRange,
        totalCostUSD: summary.cost.totalUSD,
        costSources: {
          native: summary.cost.nativeSessions,
          estimated: summary.cost.estimatedSessions,
        },
        tokens: summary.tokens,
        duration: summary.duration,
        topModels: Object.keys(summary.byModel).slice(0, 5),
        topEfforts: Object.keys(summary.byEffort).slice(0, 5),
        topTools: topTools,
      };
      writeStdout(JSON.stringify(compactOut, null, 2) + "\n");
    } else {
      writeStdout(outPath + "\n");
    }

    $.exit(0);
  } catch (err) {
    var msg = err && err.message ? err.message : String(err);
    writeStderr("extract_usage.js: error: " + msg + "\n");
    $.exit(2);
  }
}
