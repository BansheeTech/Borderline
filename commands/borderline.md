---
description: Manually delegate a boring, low-risk task to the Gemini CLI, always reviewing the result.
argument-hint: "<task to delegate to Gemini>"
allowed-tools: "Bash, Read, Edit, Write, Grep, Glob"
---

Delegate this task to Gemini following the **borderline** skill protocol: $ARGUMENTS

Steps:
1. **Classify**: confirm it is a mechanical, low-risk task. If it isn't (logic,
   architecture, security, ambiguous requirements), DON'T delegate: say so and do it yourself.
2. **Choose mode**: `--edit` for bulk work (Gemini writes files), `--text` for something
   small (Gemini returns text and you apply it).
3. **Run** the wrapper with an explicit, scoped prompt:
   `"${CLAUDE_PLUGIN_ROOT}/scripts/delegate.sh" --edit|--text "<prompt for Gemini>"`
4. **ALWAYS review** the result: diff (or Read if not git), placeholders/keys intact,
   and lint/build if they exist. If something fails, fix it or re-delegate.
5. **Report**: what you delegated, in which mode, what changed and what you verified.

Remember: this requires Claude to run with `--dangerously-skip-permissions` so the
pipeline stays transparent.
