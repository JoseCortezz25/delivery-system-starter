#!/usr/bin/env bash
# Unified launcher for decodex-usage telemetry extraction.
# Supports --engine auto|python|js (default: auto).
# Safely detects Python 3.9+ without triggering the macOS Xcode CLT popup,
# and falls back to built-in macOS osascript (JXA) when needed.

set -u

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PY_SCRIPT="$SCRIPT_DIR/extract_usage.py"
JS_SCRIPT="$SCRIPT_DIR/extract_usage.js"

ENGINE="auto"
FORWARD_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine)
      if [[ $# -lt 2 ]]; then
        echo "extract_usage.sh: error: --engine requires a value (auto, python, or js)." >&2
        exit 2
      fi
      ENGINE="$2"
      shift 2
      ;;
    --engine=*)
      ENGINE="${1#--engine=}"
      shift
      ;;
    *)
      FORWARD_ARGS+=("$1")
      shift
      ;;
  esac
done

case "$ENGINE" in
  auto|python|js) ;;
  *)
    echo "extract_usage.sh: error: invalid --engine '$ENGINE'. Choose from: auto, python, js." >&2
    exit 2
    ;;
esac

OS_NAME="$(uname -s 2>/dev/null || /usr/bin/uname -s 2>/dev/null || echo unknown)"

is_macos_stub_python() {
  local bin_path="$1"
  if [[ "$OS_NAME" == "Darwin" && "$bin_path" == "/usr/bin/python3" ]]; then
    if ! xcode-select -p >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

python_is_usable() {
  local cmd=("$@")
  "${cmd[@]}" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1
}

PYTHON_CMD=()
detect_python() {
  local resolved=""

  if resolved="$(command -v python3 2>/dev/null)"; then
    if ! is_macos_stub_python "$resolved"; then
      if python_is_usable "$resolved"; then
        PYTHON_CMD=("$resolved")
        return 0
      fi
    fi
  fi

  if resolved="$(command -v python 2>/dev/null)"; then
    if ! is_macos_stub_python "$resolved"; then
      if python_is_usable "$resolved"; then
        PYTHON_CMD=("$resolved")
        return 0
      fi
    fi
  fi

  if resolved="$(command -v py 2>/dev/null)"; then
    if python_is_usable "$resolved" -3; then
      PYTHON_CMD=("$resolved" -3)
      return 0
    fi
  fi

  return 1
}

has_jxa() {
  [[ "$OS_NAME" == "Darwin" && -x "/usr/bin/osascript" ]]
}

run_python() {
  if [[ ${#FORWARD_ARGS[@]} -gt 0 ]]; then
    "${PYTHON_CMD[@]}" "$PY_SCRIPT" "${FORWARD_ARGS[@]}"
  else
    "${PYTHON_CMD[@]}" "$PY_SCRIPT"
  fi
}

run_jxa() {
  if [[ ${#FORWARD_ARGS[@]} -gt 0 ]]; then
    /usr/bin/osascript -l JavaScript "$JS_SCRIPT" "${FORWARD_ARGS[@]}"
  else
    /usr/bin/osascript -l JavaScript "$JS_SCRIPT"
  fi
}

case "$ENGINE" in
  python)
    if ! detect_python; then
      echo "extract_usage.sh: error: Python 3.9+ is not available on this machine." >&2
      exit 1
    fi
    run_python
    exit $?
    ;;
  js)
    if ! has_jxa; then
      echo "extract_usage.sh: error: JXA engine (--engine js) requires macOS with /usr/bin/osascript." >&2
      exit 1
    fi
    run_jxa
    exit $?
    ;;
  auto)
    if detect_python; then
      if run_python; then
        exit 0
      fi
      py_exit=$?
      if has_jxa; then
        echo "extract_usage.sh: warning: Python extractor exited with status $py_exit; falling back to macOS JXA engine." >&2
        run_jxa
        exit $?
      fi
      exit "$py_exit"
    fi

    if has_jxa; then
      run_jxa
      exit $?
    fi

    echo "extract_usage.sh: error: neither Python 3.9+ nor macOS /usr/bin/osascript is available." >&2
    exit 1
    ;;
esac
