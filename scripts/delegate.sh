#!/usr/bin/env bash
# Borderline — delegate a task to the Gemini CLI in a transparent way.
#
# Usage:
#   delegate.sh --text "<prompt>"   # Gemini ONLY returns text (read-only, never touches files)
#   delegate.sh --edit "<prompt>"   # Gemini works autonomously in the repo (--yolo, reads and writes)
#
# Default mode: --text (the safest one).
#
# Output convention: Gemini's useful output goes to stdout.
# Pipeline markers ('>>> borderline ...') go to stderr so Claude can
# separate the result from the noise.

set -euo pipefail

MODE="text"
case "${1:-}" in
  --text) MODE="text"; shift ;;
  --edit) MODE="edit"; shift ;;
  --*)    echo "borderline: unknown flag '$1' (use --text or --edit)" >&2; exit 2 ;;
esac

PROMPT="${1:-}"
if [[ -z "${PROMPT}" ]]; then
  echo "borderline: missing prompt. Usage: delegate.sh [--text|--edit] \"<prompt>\"" >&2
  exit 2
fi

if ! command -v gemini >/dev/null 2>&1; then
  echo "borderline: 'gemini' is not installed or not on the PATH." >&2
  echo "borderline: install it (e.g. 'brew install gemini-cli' or via npm) and retry." >&2
  exit 127
fi

echo ">>> borderline → gemini  [mode: ${MODE}]  dir: $(pwd)" >&2
echo ">>> task: ${PROMPT}" >&2

if [[ "${MODE}" == "edit" ]]; then
  # Gemini auto-accepts its own tools (including Write/Edit).
  # --skip-trust avoids the workspace trust prompt in headless mode.
  exec gemini --yolo --skip-trust -p "${PROMPT}"
else
  # Read-only mode: Gemini may read context but NEVER writes.
  # Claude is responsible for applying the result.
  exec gemini --approval-mode plan --skip-trust -p "${PROMPT}"
fi
