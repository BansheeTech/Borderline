#!/usr/bin/env bash
# Borderline — delegate a task to the Antigravity CLI (agy) in a transparent way.
#
# Usage:
#   delegate.sh --text "<prompt>"     # agy returns text only; you (Claude) apply it
#   delegate.sh --edit "<prompt>"     # agy edits the named files itself, tightly scoped
#   delegate.sh --text @/path/to/file # read the prompt from a file (no argv size limit)
#   delegate.sh --text -              # read the prompt from STDIN  (no argv size limit)
#
# Default mode: --text.
#
# WHY @file / - EXIST: the command line itself is bounded by ARG_MAX (~1 MB on macOS).
# A prompt big enough to cross it can't even reach this script as an argument — the
# shell refuses with "Argument list too long" before the script runs. For genuinely
# large content (big i18n batches, long documents), write it to a temp file and pass
# `@that-file` (tiny argv), or pipe it on stdin with `-`. delegate.sh then streams the
# whole thing to agy on stdin, which has no size ceiling.
#
# THE PROMPT GOES IN ON STDIN — never as a -p argument.
#   A command-line argument is bounded by the OS ARG_MAX (~1 MB on macOS). The moment
#   the prompt (preamble + your text) crosses that ceiling, the kernel refuses to exec
#   agy at all: "Argument list too long". That is the "it hangs / fails on long
#   context" bug — a big i18n batch or a long document silently blows the argv limit,
#   and the old code then mis-reported the empty result as a rate-limit. STDIN has no
#   such ceiling: a 1.3 MB prompt that is impossible to pass via -p streams in fine.
#   So we ALWAYS pipe the prompt to `agy --print` on stdin (no -p). This is also how
#   the prompt was effectively fed before — large contexts "just work" again.
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
# agy's rate-limit is SILENT: it throttles by request frequency and HANGS instead of
# returning a 429. Worse, agy's own --print-timeout does NOT always fire on this hang
# (it bounds the model-wait, not input ingestion), so the call can hang far past it.
# This wrapper therefore enforces its own HARD wall-clock watchdog: if agy overruns
# the timeout (plus a grace margin) it is killed and we return control instead of
# hanging forever. "Empty at timeout" is flagged so you can tell a throttle apart
# from a real hang. Do not hammer-retry or run calls concurrently — both make it worse.
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

# Accept the prompt from a file (@path) or stdin (-) so content larger than ARG_MAX
# can get through — passing it as a literal argument would fail before this runs.
if [[ "${PROMPT}" == "-" ]]; then
  PROMPT="$(cat)"
elif [[ "${PROMPT}" == @* && -r "${PROMPT#@}" ]]; then
  PROMPT="$(cat -- "${PROMPT#@}")"
fi
if [[ -z "${PROMPT}" ]]; then
  echo "borderline: prompt resolved to empty (check the @file path or stdin)." >&2
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

# Parse a duration ("90s", "2m", "1h", or bare seconds) into whole seconds.
to_seconds() {
  local t="${1:-}"
  if [[ "${t}" =~ ^([0-9]+)([smh]?)$ ]]; then
    local n="${BASH_REMATCH[1]}" unit="${BASH_REMATCH[2]}"
    case "${unit}" in
      h) echo $(( n * 3600 )) ;;
      m) echo $(( n * 60 )) ;;
      *) echo "${n}" ;;
    esac
  else
    echo 120
  fi
}

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
OUT_FILE=""
WD_FLAG=""
PROMPT_FILE=""
cleanup() {
  cd / 2>/dev/null || true
  [[ -n "${OUT_FILE}" ]] && rm -f "${OUT_FILE}"
  [[ -n "${WD_FLAG}" ]] && rm -f "${WD_FLAG}"
  [[ -n "${PROMPT_FILE}" ]] && rm -f "${PROMPT_FILE}"
  [[ -n "${SCRATCH}" ]] && rm -rf "${SCRATCH}"
  # MUST end on success: an EXIT trap whose last command fails (e.g. the [[ -n ]]
  # test above when a var is empty) clobbers the script's real exit code in bash 3.2.
  return 0
}
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
# Preview the task without dumping a huge prompt to stderr.
if [[ "${#PROMPT}" -gt 280 ]]; then
  echo ">>> task (${#PROMPT} chars): ${PROMPT:0:280}…" >&2
else
  echo ">>> task: ${PROMPT}" >&2
fi

if [[ "${THROTTLE_MS}" -gt 0 ]]; then
  echo ">>> borderline: throttling ${THROTTLE_MS}ms before call (rate-limit avoidance)" >&2
  # ms → seconds with ms precision; sleep accepts decimals on BSD and GNU.
  sleep "$(printf '%d.%03d' "$(( THROTTLE_MS / 1000 ))" "$(( THROTTLE_MS % 1000 ))")"
fi

# Hard wall-clock guard. agy's --print-timeout bounds the model wait but NOT input
# ingestion / a silent rate-limit hang, so we add our own backstop slightly longer
# than --print-timeout: normally --print-timeout fires first (clean), and this only
# fires when agy is genuinely stuck — guaranteeing the wrapper returns control.
HARD_SECS=$(( $(to_seconds "${TIMEOUT}") + 30 ))
OUT_FILE="$(mktemp -t borderline-out.XXXXXX)"
WD_FLAG="$(mktemp -t borderline-wd.XXXXXX)"
rm -f "${WD_FLAG}"   # absent = watchdog has not fired; present = it killed agy

# Stage the full prompt (preamble + task) in a file and feed it to agy by REDIRECTING
# stdin from that file — not through a `printf | agy` pipe. A redirected regular file
# gives agy a clean EOF the instant it finishes reading; a pipe can leave a writer FD
# open in a child (the watchdog) and stall a reader that waits for EOF. Stdin also has
# no ARG_MAX ceiling, so arbitrarily long prompts get through (the whole point of -p
# being gone). stdout (the result) → OUT_FILE; stderr (agy's logs) flows through.
PROMPT_FILE="$(mktemp -t borderline-prompt.XXXXXX)"
printf '%s\n%s\n' "${PREAMBLE}" "${PROMPT}" > "${PROMPT_FILE}"

cd "${RUNDIR}"
"${CLI}" --print --dangerously-skip-permissions \
    --model "${MODEL}" --print-timeout "${TIMEOUT}" \
    <"${PROMPT_FILE}" >"${OUT_FILE}" &
AGY_PID=$!

(
  # Watchdog: sleep, then kill agy if it is still alive past the hard deadline.
  # Touch WD_FLAG *before* killing so the parent can reliably tell a timeout-kill
  # apart from a normal empty return (no race with the TERM→KILL grace window).
  sleep "${HARD_SECS}"
  if kill -0 "${AGY_PID}" 2>/dev/null; then
    : > "${WD_FLAG}"
    kill -TERM "${AGY_PID}" 2>/dev/null || true
    sleep 2
    kill -KILL "${AGY_PID}" 2>/dev/null || true
  fi
) &
WATCH_PID=$!

rc=0
wait "${AGY_PID}" 2>/dev/null || rc=$?

# Stop the watchdog so we don't linger until HARD_SECS on a fast, healthy call.
kill -TERM "${WATCH_PID}" 2>/dev/null || true
wait "${WATCH_PID}" 2>/dev/null || true

KILLED_BY_WATCHDOG=0
[[ -f "${WD_FLAG}" ]] && KILLED_BY_WATCHDOG=1

RESULT="$(cat "${OUT_FILE}" 2>/dev/null || true)"

printf '%s' "${RESULT}"
[[ -n "${RESULT}" ]] && printf '\n'

# A watchdog kill is an unambiguous failure in BOTH modes — agy was genuinely stuck.
if [[ "${KILLED_BY_WATCHDOG}" -eq 1 ]]; then
  {
    echo "borderline: HARD TIMEOUT after ${HARD_SECS}s — agy did not return and was killed."
    echo "borderline: agy's own --print-timeout (${TIMEOUT}) did not fire, which points to a"
    echo "borderline: SILENT RATE-LIMIT or an input-ingestion stall, not a crash. Do NOT"
    echo "borderline: hammer-retry (worsens the block) and do NOT run calls concurrently. Let"
    echo "borderline: agy REST several minutes, then send ONE call. For batch i18n, set"
    echo "borderline: BORDERLINE_THROTTLE_MS=3000–5000 and prefer one big --text batch."
  } >&2
  exit 124
fi

if [[ "${MODE}" == "edit" ]]; then
  # In --edit, agy writes the files; its stdout is often empty and its exit code in
  # print mode is unreliable (it can report non-zero even after a correct edit). The
  # mandatory diff review is the real gate, so don't hard-fail on those — just surface
  # a note and let Claude confirm by reviewing the diff.
  if [[ "${rc}" -ne 0 ]]; then
    echo "borderline: agy reported exit ${rc} in --edit mode — often spurious when it still" >&2
    echo "borderline: made the edits. REVIEW THE DIFF to confirm the change before trusting it." >&2
  fi
  exit 0
fi

# --text: a usable result must be a clean exit AND non-empty output.
if [[ "${rc}" -eq 0 && -n "${RESULT}" ]]; then
  exit 0
fi

if [[ -z "${RESULT}" ]]; then
  {
    echo "borderline: agy returned EMPTY (exit ${rc})."
    echo "borderline: this is almost always a SILENT RATE-LIMIT — agy throttles by request"
    echo "borderline: frequency and returns nothing instead of a 429. Do NOT hammer-retry"
    echo "borderline: (it worsens the block) and do NOT run calls concurrently. Let agy REST"
    echo "borderline: several minutes, then send ONE call. For batch i18n, set"
    echo "borderline: BORDERLINE_THROTTLE_MS=3000–5000 and prefer one big --text batch."
  } >&2
else
  echo "borderline: agy exited ${rc} with the output above; review before trusting it." >&2
fi
# Empty --text output is unusable even if agy exited 0 (a silent rate-limit can return
# nothing with a 0 status), so always fail non-zero here so the caller doesn't mistake
# an empty result for success.
if [[ "${rc}" -eq 0 ]]; then
  exit 1
fi
exit "${rc}"
