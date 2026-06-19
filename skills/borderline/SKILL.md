---
name: borderline
description: >-
  Delegate mechanical, boring, low-risk tasks to the Antigravity CLI (agy) where
  it is just as reliable as Claude: bulk translations and i18n, trivial CSS/color/style
  changes, repetitive renames and replacements across many files, boilerplate,
  formatting and simple copy rewrites. Use it when the task is monotonous, its
  correctness is verifiable at a glance, and being wrong is cheap. Do NOT use it
  for business logic, architecture decisions, security, ambiguous requirements,
  or changes where a mistake is costly.
argument-hint: "<task to delegate to agy>"
---

# Borderline — transparent Claude ⇄ agy pipeline

Borderline exists to **offload boring, safe work to the Antigravity CLI (`agy`)** so
Claude can stay focused on what needs judgment. Communication must be **transparent**:
always tell the user what you delegated, in which mode, and what you reviewed.

> **Operating requirement:** this flow launches `agy` via `Bash` without asking
> for permission on every step, so Claude must run with `--dangerously-skip-permissions`.
> Otherwise every call prompts for confirmation and the pipeline stops being transparent.

> **`agy` is agentic.** Left alone it scans the repository and "explores for context"
> before doing anything — slow and useless for the mechanical tasks we delegate. The
> wrapper (`delegate.sh`) injects a strict preamble that forbids that exploration, so
> agy does the concrete task and nothing more. **Always go through the wrapper.**

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
| `--text` | **Small / context-free** work (one color, one string, a batch of strings to translate) | agy uses **no tools** and **only returns text**; you apply it with Edit/Write |
| `--edit` | **Bulk** file work (mass i18n across files, replacements across many files) | agy reads and **writes** the named files itself (`--dangerously-skip-permissions`), scoped to those files |

**Prefer `--text` for translations.** Instead of pointing agy at repo files (which is
exactly what triggers its agentic scanning), **paste the source content inline** in the
prompt and ask for the translated output only — then Claude writes the file. This is
faster, cheaper, and avoids divagation entirely. Reach for `--edit` only when the volume
of files makes inlining impractical.

## 3. Run the delegation

Always call the wrapper (it centralizes flags, the anti-exploration preamble, model and mode):

```bash
# Preferred for translations: inline the source, get output only, you write the file.
"${CLAUDE_PLUGIN_ROOT}/scripts/delegate.sh" --text 'Translate this JSON object to neutral Spanish. Output ONLY the translated JSON, same keys/order, do NOT touch {var} placeholders or HTML tags:
{"save":"Save","cancel":"Cancel","items":"You have {n} items"}'
```

```bash
# Bulk across files when inlining is impractical.
"${CLAUDE_PLUGIN_ROOT}/scripts/delegate.sh" --edit "Translate ALL keys in locales/en.json and write locales/es.json with the same keys, neutral Spanish, without touching {var} placeholders or HTML tags. Operate only on those two files."
```

```bash
# Tiny text answer.
"${CLAUDE_PLUGIN_ROOT}/scripts/delegate.sh" --text "Give me only the hex of a blue 20% darker than #3B82F6. Reply with the value only."
```

Rules when building the prompt for agy:
- Be **explicit and scoped**: exact files (in `--edit`), output format, what NOT to touch
  (placeholders `{var}`, `%s`, tags, keys, ordering).
- In `--text`, ask for **the result only** (no explanations) so you can apply it cleanly,
  and **include the source content inline** so agy needs no repo access.
- In `--edit`, **name the input and output files** and the success criteria, and remind it
  to operate only on those files.

Tunables (env vars, optional): `BORDERLINE_MODEL` (default `Gemini 3.5 Flash (High)`),
`BORDERLINE_TIMEOUT` (default `4m`), `BORDERLINE_CLI` (default `agy`),
`BORDERLINE_TEXT_SKIP_PERMS=1` (auto-approve in `--text` too, if a pure-text task ever hangs).

## 4. ALWAYS review (non-negotiable)

After delegating, **verify before accepting**:
1. **Diff**: if it's a git repo, `git diff --stat` then `git diff` of the touched files.
   If it's not git, `Read` the files agy was supposed to change.
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

Example: *"Delegated to agy (--edit mode) the translation of 142 keys into
`locales/es.json`. Reviewed the diff: keys aligned with `en.json`, placeholders intact,
`lint` OK."*

## Common errors
- `agy: command not found` / exit 127 → the Antigravity CLI is not installed/on PATH.
  **Do NOT try to install it yourself.** It requires the user to sign in, so an unattended
  install would be useless. Just hand the user the URL and ask them to install it **and sign
  in**, then retry: **https://antigravity.google/product/antigravity-cli** . (Override the
  binary with `BORDERLINE_CLI` if it lives elsewhere.)
- agy hangs / `Error: timed out waiting for response` → usually multiple concurrent `agy`
  sessions contending, or a task that isn't truly context-free trying to use a tool in
  `--text`. Run one delegation at a time; for `--text` make sure the source is inline; or
  use `--edit` if the task genuinely needs file access.
- agy starts exploring/auditing the repo → the wrapper wasn't used. Always go through
  `delegate.sh`; its preamble is what suppresses the agentic exploration.
