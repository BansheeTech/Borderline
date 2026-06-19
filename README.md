# Borderline

<p align="center">
  <img src="img/Borderline.png" alt="Borderline" />
</p>

A Claude Code plugin that **delegates to the Antigravity CLI** (`agy`) the boring,
mechanical, low-risk tasks where it is just as reliable as Claude: bulk
translations and **i18n**, trivial style/color changes, repetitive renames and
replacements, boilerplate. The idea: a **transparent** Claude ⇄ agy pipeline, so
Claude stays reserved for what needs judgment.

## How it works

- **`borderline` skill** (`skills/borderline/SKILL.md`): the brain. It decides what is
  delegable, picks the mode, launches agy and **always reviews** the result. It
  auto-activates when it detects a borderline task.
- **`/borderline <task>` command**: explicit manual delegation.
- **`scripts/delegate.sh`**: a wrapper around `agy` with two modes:
  - `--text` → runs agy from an **empty scratch directory** and returns text only; Claude
    applies the result. Preferred for translations (inline the source) and small changes.
  - `--edit` → runs agy in the repo, reading and writing the named files. For bulk work.

Because `agy` is **agentic** — it takes the working directory as its workspace and scans it
("reads the README", lists files, opens scripts) before answering, even with a concrete
prompt — the real fix is structural: `--text` runs agy from an **empty directory**, so there
is no workspace to explore and no rate-limit quota wasted on it. Each of those exploratory
reads is a request against agy's limit, which is why divagation also exhausts the quota.
Always go through `delegate.sh`.

**Long context works regardless of size.** The wrapper streams the prompt to `agy --print`
on **stdin**, never as a `-p` argument — so a large i18n batch or long document can't blow the
shell's `ARG_MAX` ceiling (the old "Argument list too long" / silent hang on long prompts).
For content too large to even fit on `delegate.sh`'s own command line, write it to a temp file
and pass `--text @/path/to/file` (or pipe it and pass `-`); a 1.3 MB prompt that is impossible
via `-p` goes through cleanly.

The wrapper also bounds agy's **silent rate-limit** (agy throttles by request frequency and
hangs returning empty instead of a 429). agy's own `--print-timeout` doesn't always fire on
this stall, so the wrapper adds a **hard wall-clock watchdog** (`--print-timeout` + 30 s) that
kills a stuck call and prints `borderline: HARD TIMEOUT …` — the agent never hangs forever.
Don't hammer-retry or run calls concurrently — both make throttling worse; for batch i18n,
space calls with `BORDERLINE_THROTTLE_MS=3000`–`5000`.

Design decisions (set in this build):
- **Hybrid** by task: agy edits in bulk / returns text for small things.
- **Hybrid** activation: automatic (skill) + manual (`/borderline`).
- **Always review**: Claude verifies the diff before accepting anything.

## Requirements

- [Antigravity CLI](https://antigravity.google/product/antigravity-cli) (`agy`) installed and
  on the `PATH` (`agy --help`).
- Claude Code running with **`--dangerously-skip-permissions`**, so the pipeline is
  transparent and doesn't prompt for confirmation on every call.

## Installation

```bash
# In Claude Code:
/plugin marketplace add BansheeTech/Borderline
/plugin install borderline@borderline-marketplace
```

Then launch Claude with:

```bash
claude --dangerously-skip-permissions
```

## Usage

- **Automatic**: ask Claude for something borderline ("translate the locales to French",
  "switch the background to dark mode") and the skill will delegate to agy and report back.
- **Manual**: `/borderline translate locales/en.json to locales/de.json`.

## Structure

```
Borderline/
├── .claude-plugin/
│   ├── plugin.json          # plugin manifest
│   └── marketplace.json     # to install as a local marketplace
├── skills/borderline/SKILL.md
├── commands/borderline.md
├── scripts/delegate.sh
└── README.md
```
