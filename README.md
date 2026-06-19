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
  - `--edit` → agy works in the repo (`agy --print --dangerously-skip-permissions -p`),
    reading and writing the named files. For bulk work (mass i18n).
  - `--text` → agy only returns text (`agy --print -p`, no tools), never
    touching files; Claude applies the result. Preferred for translations (inline the
    source) and small changes.

Because `agy` is **agentic** — it scans the repo and "explores for context" by default —
the wrapper injects a strict preamble that forbids that exploration, so agy does the
concrete task instead of divagating. Always go through `delegate.sh`.

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
