#!/usr/bin/env bash
# Borderline — delegate a task to the Antigravity CLI (agy) in a transparent way.
#
# Usage:
#   delegate.sh --text "<prompt>"   # agy returns text only; you (Claude) apply it
#   delegate.sh --edit "<prompt>"   # agy edits the named files itself, tightly scoped
#
# Default mode: --text.
#
# THE KEY INSIGHT — run agy from an EMPTY directory.
#   agy is agentic: it takes the current working directory as its "workspace" and
#   EXPLORES it (lists files, reads README, opens scripts) before answering — even
#   when you give it a concrete prompt, and even when the prompt says "don't". Each
#   of those reads is a request against agy's rate-limit, so a translation that needs
#   zero repo context ends up scanning the whole repo and burning the quota.
#
#   The fix is structural, not a prompt plea: for --text we run agy from a fresh
#   EMPTY scratch dir. No workspace → nothing to scan → no divagation, no wasted
#   requests. (--edit must run in the repo because it has to read/write real files.)
#
# Pure read-only --print (without --dangerously-skip-permissions) is broken on
# current agy builds — agy attempts a tool-call, the denial derails it, and it
# returns chatter instead of the result. So both modes auto-approve; in --text the
# empty scratch dir is what guarantees it can't touch your files.
#
# agy's rate-limit is SILENT: it throttles by request frequency and HANGS to the
# timeout returning empty instead of a 429. This wrapper flags "empty at timeout"
# so you can tell a throttle apart from a real hang. Do not hammer-retry or kill
# calls mid-flight — both make the block worse.
#
# Output convention: agy's result goes to stdout. Markers ('>>> borderline ...')
# and diagnostics go to stderr so Claude can separate result from noise.
#
# Tunables (env vars, all optional):
#   BORDERLINE_CLI          binary to call                (default: agy)
#   BORDERLINE_MODEL        model for the session         (default: "Gemini 3.5 Flash (High)")
#   BORDERLINE_TIMEOUT      --print-timeout value         (default: 2m)
#   BORDERLINE_THROTTLE_MS  sleep before the call         (default: 0; set 3000–5000 for batch i18n)

set -euo pipefail

CLI="${BORDERLINE_CLI:-agy}"
MODEL="${BORDERLINE_MODEL:-Gemini 3.5 Flash (High)}"
TIMEOUT="${BORDERLINE_TIMEOUT:-2m}"
THROTTLE_MS="${BORDERLINE_THROTTLE_MS:-0}"

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

# Defense-in-depth preambles (the empty scratch dir is the real guard for --text).
read -r -d '' TEXT_PREAMBLE <<'EOF' || true
You are a precise, literal text-transformation tool. These rules have NO exceptions:
- Do NOT use any tools. Do NOT read, list, search, open, or edit any files. Do NOT
  explore or scan the workspace. Do NOT run commands.
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

# Where agy runs decides whether it divagates. --text → empty scratch dir; --edit → repo.
SCRATCH=""
cleanup() { [[ -n "${SCRATCH}" ]] && rm -rf "${SCRATCH}"; }
trap cleanup EXIT

if [[ "${MODE}" == "edit" ]]; then
  PREAMBLE="${EDIT_PREAMBLE}"
  RUNDIR="$(pwd)"
else
  PREAMBLE="${TEXT_PREAMBLE}"
  SCRATCH="$(mktemp -d -t borderline-scratch.XXXXXX)"
  RUNDIR="${SCRATCH}"
fi

echo ">>> borderline → ${CLI}  [mode: ${MODE}]  [model: ${MODEL}]  [timeout: ${TIMEOUT}]  rundir: ${RUNDIR}" >&2
echo ">>> task: ${PROMPT}" >&2

if [[ "${THROTTLE_MS}" -gt 0 ]]; then
  echo ">>> borderline: throttling ${THROTTLE_MS}ms before call (rate-limit avoidance)" >&2
  # ms → seconds with ms precision; sleep accepts decimals on BSD and GNU.
  sleep "$(printf '%d.%03d' "$(( THROTTLE_MS / 1000 ))" "$(( THROTTLE_MS % 1000 ))")"
fi

# Run agy from RUNDIR. Capture stdout (the result); let stderr (logs) flow as noise.
rc=0
RESULT="$( cd "${RUNDIR}" && "${CLI}" --print --dangerously-skip-permissions \
  --model "${MODEL}" --print-timeout "${TIMEOUT}" \
  -p "${PREAMBLE}
${PROMPT}" )" || rc=$?

printf '%s' "${RESULT}"
[[ -n "${RESULT}" ]] && printf '\n'

if [[ "${rc}" -eq 0 && -n "${RESULT}" ]]; then
  exit 0
fi

if [[ -z "${RESULT}" ]]; then
  {
    echo "borderline: agy returned EMPTY after ${TIMEOUT} (exit ${rc})."
    echo "borderline: this is almost always a SILENT RATE-LIMIT — agy throttles by request"
    echo "borderline: frequency and HANGS instead of returning a 429. Do NOT hammer-retry"
    echo "borderline: (it worsens the block) and do NOT kill calls mid-flight (counts against"
    echo "borderline: quota). Let agy REST several minutes, then send ONE call. For batch i18n,"
    echo "borderline: set BORDERLINE_THROTTLE_MS=3000–5000 and prefer one big --text batch."
  } >&2
else
  echo "borderline: agy exited ${rc} with the output above; review before trusting it." >&2
fi
exit "${rc:-1}"
