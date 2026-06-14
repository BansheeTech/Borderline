---
name: borderline
description: >-
  Delegate mechanical, boring, low-risk tasks to the Gemini CLI where Gemini is
  just as reliable as Claude: bulk translations and i18n, trivial CSS/color/style
  changes, repetitive renames and replacements across many files, boilerplate,
  formatting and simple copy rewrites. Use it when the task is monotonous, its
  correctness is verifiable at a glance, and being wrong is cheap. Do NOT use it
  for business logic, architecture decisions, security, ambiguous requirements,
  or changes where a mistake is costly.
argument-hint: "<task to delegate to Gemini>"
---

# Borderline — transparent Claude ⇄ Gemini pipeline

Borderline exists to **offload boring, safe work to Gemini** so Claude can stay
focused on what needs judgment. Communication must be **transparent**: always tell
the user what you delegated, in which mode, and what you reviewed.

> **Operating requirement:** this flow launches `gemini` via `Bash` without asking
> for permission on every step, so Claude must run with `--dangerously-skip-permissions`.
> Otherwise every call prompts for confirmation and the pipeline stops being transparent.

## 1. Is it a *borderline* task? (classify first)

**DO delegate** — mechanical, repetitive, verifiable at a glance:
- Bulk translations and **i18n** (translate/populate `locales/*.json`, `.po`, `messages.*`).
- Trivial style changes: background/text color, spacing, CSS token swaps.
- Repetitive renames and replacements across many files (same pattern N times).
- Predictable boilerplate, sample data/fixtures, formatting, simple copy rewrites.

**DON'T delegate** — keep it in Claude:
- Business logic, algorithms, concurrency, state.
- Architecture, API design, decisions with trade-offs.
- Security, auth, secret handling, data migrations.
- Anything with ambiguous requirements or where a mistake is costly.

When in doubt, **don't delegate**: do it yourself.

## 2. Choose the mode

| Mode | When | What it does |
|------|------|--------------|
| `--edit` | **Bulk** work (mass i18n, replacements across many files) | Gemini reads and **writes** files itself (`--yolo`) |
| `--text` | **Small** things (one color, one string, a short translation) | Gemini **only returns text**; you apply it with Edit/Write |

## 3. Run the delegation

Always call the wrapper (it centralizes flags, trust and mode):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/delegate.sh" --edit "Translate ALL keys in locales/en.json and write locales/es.json with the same keys, neutral Spanish, without touching {var} placeholders or HTML tags."
```

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/delegate.sh" --text "Give me only the hex of a blue 20% darker than #3B82F6. Reply with the value only."
```

Rules when building the prompt for Gemini:
- Be **explicit and scoped**: exact files, output format, what NOT to touch
  (placeholders `{var}`, `%s`, tags, keys, ordering).
- In `--text`, ask for **the result only** (no explanations) so you can apply it cleanly.
- In `--edit`, name the input and output files and the success criteria.

## 4. ALWAYS review (non-negotiable)

After delegating, **verify before accepting**:
1. **Diff**: if it's a git repo, `git diff --stat` then `git diff` of the touched files.
   If it's not git, `Read` the files Gemini was supposed to change.
2. **Sanity**: for i18n, keys must match the source with none missing/extra, and
   placeholders must stay intact. For style, the value must be the requested one.
3. **Build/lint** if they exist and are fast (`npm run lint`, `tsc --noEmit`, etc.).
4. If something is wrong: fix it yourself or **re-delegate** with more precise
   instructions. Never let dubious work through.

## 5. Report (transparency)

Always close with one or two lines stating:
- What you delegated and in which mode (`--edit`/`--text`).
- What changed (files / number of strings).
- What you verified and the result (diff reviewed, lint OK, etc.).

Example: *"Delegated to Gemini (--edit mode) the translation of 142 keys into
`locales/es.json`. Reviewed the diff: keys aligned with `en.json`, placeholders intact,
`lint` OK."*

## Common errors
- `gemini: command not found` → the CLI is not installed/on PATH; tell the user.
- Gemini hangs asking for confirmation → Claude is missing `--dangerously-skip-permissions`,
  or the wrapper wasn't used (it already passes `--yolo`/`--skip-trust`).
