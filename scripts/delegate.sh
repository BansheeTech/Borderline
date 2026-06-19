#!/usr/bin/env bash
# Borderline — delegate a task to the Antigravity CLI (agy) in a transparent way.
#
# Usage:
#   delegate.sh --text "<prompt>"   # agy ONLY returns text (no tools, never touches files)
#   delegate.sh --edit "<prompt>"   # agy works in the repo (auto-approves writes), tightly scoped
#
# Default mode: --text (the safest one).
#
# Why a wrapper: agy is AGENTIC. Left to itself it scans the repository and
# "explores for context" before doing anything — useless and slow for the
# mechanical tasks Borderline delegates (translations, renames, color swaps).
# This wrapper injects a strict preamble that forbids that exploration so agy
# does the concrete task and nothing else.
#
# Output convention: agy's useful output goes to stdout.
# Pipeline markers ('>>> borderline ...') go to stderr so Claude can
# separate the result from the noise.
#
# Tunables (env vars, all optional):
#   BORDERLINE_CLI       binary to call            (default: agy)
#   BORDERLINE_MODEL     model for the session     (default: "Gemini 3.5 Flash (High)")
#   BORDERLINE_TIMEOUT   --print-timeout value     (default: 4m)
#   BORDERLINE_TEXT_SKIP_PERMS=1  also auto-approve in --text mode (avoids hangs if
#                        agy insists on a tool; loses the hard read-only guarantee)

set -euo pipefail

CLI="${BORDERLINE_CLI:-agy}"
MODEL="${BORDERLINE_MODEL:-Gemini 3.5 Flash (High)}"
TIMEOUT="${BORDERLINE_TIMEOUT:-4m}"

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

if ! command -v "${CLI}" >/dev/null 2>&1; then
  echo "borderline: '${CLI}' is not installed or not on the PATH." >&2
  echo "borderline: ask the USER to install the Antigravity CLI and sign in — it can't be" >&2
  echo "borderline: installed unattended (login required). Hand them this URL:" >&2
  echo "borderline:   https://antigravity.google/product/antigravity-cli" >&2
  echo "borderline: (override the binary with BORDERLINE_CLI if it lives elsewhere)." >&2
  exit 127
fi

# Strict preambles that keep agy on-task and stop it from exploring the repo.
read -r -d '' TEXT_PREAMBLE <<'EOF' || true
You are a precise, literal text-transformation tool. These rules have NO exceptions:
- Do NOT use any tools. Do NOT read, list, search, open, or edit any files. Do NOT
  explore or scan the repository or workspace. Do NOT run commands.
- Work ONLY from the text contained in this prompt. Do not seek additional context.
- Reply IMMEDIATELY with ONLY the requested result: no preamble, no explanation,
  no markdown code fences, no commentary.

TASK:
EOF

read -r -d '' EDIT_PREAMBLE <<'EOF' || true
You are performing a single, narrowly-scoped mechanical edit. These rules have NO exceptions:
- Do EXACTLY the task described below and nothing more.
- Operate ONLY on the files explicitly named in the task. Do NOT explore, scan, audit,
  or read unrelated files or the rest of the repository "for context".
- Do NOT refactor, reformat, rename, or "improve" anything that was not requested.
- When finished, stop. Do not summarize the repository or suggest further work.

TASK:
EOF

echo ">>> borderline → ${CLI}  [mode: ${MODE}]  [model: ${MODEL}]  dir: $(pwd)" >&2
echo ">>> task: ${PROMPT}" >&2

if [[ "${MODE}" == "edit" ]]; then
  # agy auto-approves its own tools (including writes), but the preamble keeps it
  # scoped to the named files instead of wandering the whole repo.
  exec "${CLI}" --print --dangerously-skip-permissions \
    --model "${MODEL}" --print-timeout "${TIMEOUT}" \
    -p "${EDIT_PREAMBLE}
${PROMPT}"
else
  # Read-only text mode: the preamble forbids all tool use, so agy must answer
  # directly from the prompt. Without --dangerously-skip-permissions a stray tool
  # call gets denied rather than executed (so it can't touch files). Set
  # BORDERLINE_TEXT_SKIP_PERMS=1 if a pure-text task ever hangs on a permission.
  SKIP=()
  [[ "${BORDERLINE_TEXT_SKIP_PERMS:-}" == "1" ]] && SKIP=(--dangerously-skip-permissions)
  # macOS bash 3.2: guard empty-array expansion under `set -u`.
  exec "${CLI}" --print ${SKIP[@]+"${SKIP[@]}"} \
    --model "${MODEL}" --print-timeout "${TIMEOUT}" \
    -p "${TEXT_PREAMBLE}
${PROMPT}"
fi
