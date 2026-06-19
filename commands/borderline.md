---
description: Manually delegate a boring, low-risk task to the Antigravity CLI (agy), always reviewing the result.
argument-hint: "<task to delegate to agy>"
allowed-tools: "Bash, Read, Edit, Write, Grep, Glob"
---

Delegate this task to agy following the **borderline** skill protocol: $ARGUMENTS

Steps:
1. **Classify**: confirm it is a mechanical, low-risk task. If it isn't (logic,
   architecture, security, ambiguous requirements), DON'T delegate: say so and do it yourself.
2. **Choose mode**: `--text` for context-free work (agy returns text, you apply it — preferred
   for translations: inline the source content in the prompt), `--edit` for bulk file work
   (agy writes the named files itself).
3. **Run** the wrapper with an explicit, scoped prompt:
   `"${CLAUDE_PLUGIN_ROOT}/scripts/delegate.sh" --edit|--text "<prompt for agy>"`
   For a **large** prompt (big i18n batch, long document), don't inline it — write it to a temp
   file and pass the path: `… --text @/tmp/borderline-batch.txt`. Inlining a huge prompt can
   exceed the shell's `ARG_MAX` and fail; `@file` streams it to agy on stdin with no size limit.
4. **ALWAYS review** the result: diff (or Read if not git), placeholders/keys intact,
   and lint/build if they exist. If something fails, fix it or re-delegate.
5. **Report**: what you delegated, in which mode, what changed and what you verified.

Remember: this requires Claude to run with `--dangerously-skip-permissions` so the
pipeline stays transparent. `agy` is agentic — always go through `delegate.sh`, whose
preamble stops it from scanning the repo instead of doing the concrete task.
