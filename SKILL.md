---
name: cursor-cli-headless
description: Execute coding tasks using the Cursor CLI in headless print mode. Use when delegating code writing, refactoring, analysis, or review tasks to a headless Cursor agent process, running automated code changes, or batch-processing files with the agent CLI.
---

# Cursor CLI Headless

Execute coding tasks using the Cursor CLI in non-interactive (print) mode for scripts, automation, and batch processing.

## Prerequisites

- **Cursor CLI installed**: Run `agent --version`. If missing, install: `curl https://cursor.com/install -fsS | bash` (macOS/Linux/WSL) or see [Installation](https://cursor.com/docs/cli/installation).
- **Authenticated**: Set `CURSOR_API_KEY` in the environment for scripts, or run `agent login` interactively once.

## Quick start

**Inline prompt (short):**

```bash
agent -p --force "Refactor src/utils.js to use ES6+ syntax"
```

**Long prompt from file:**

```bash
agent -p --force "$(cat path/to/prompt.txt)"
```

**Using the wrapper script (recommended):**

```bash
./scripts/run-task.sh -f prompt.txt
./scripts/run-task.sh -p "Add tests for auth module" -d /path/to/project -o json
```

## Prompt handling

| Case | Command pattern |
|------|-----------------|
| Short inline | `agent -p [--force] "your prompt"` |
| Long prompt from file | `agent -p [--force] "$(cat path/to/prompt.txt)"` |

- Use `--force` when the task should **modify files**. Without it, the agent only proposes changes.
- The agent runs in the **current working directory**; `cd` to the target project first, or use the script’s `-d` option.

## Key flags

| Flag | Description |
|------|-------------|
| `-p`, `--print` | Non-interactive mode; print response to stdout |
| `--force` | Allow file modifications without confirmation |
| `--output-format` | `text` (default), `json`, or `stream-json` |
| `--stream-partial-output` | Character-level streaming (only with `stream-json`) |
| `-m`, `--model` | Model to use |
| `--mode` | `agent` (default), `plan`, or `ask` |
| `--resume [chatId]` | Resume a previous session |

## Output format selection

| Format | Use when |
|--------|----------|
| `text` | You only need the final answer; clean, no structure |
| `json` | You need to parse the result (e.g. `jq -r '.result'`); single object at end |
| `stream-json` | You need progress (model init, tool calls, partial text); NDJSON, one event per line. Use `--stream-partial-output` for character-level streaming |

## Using the wrapper script (recommended)

**Recommended.** `scripts/run-task.sh` wraps the CLI with consistent argument handling. File modifications are allowed by default; use `--no-force` to only propose changes.

**Arguments:**

- `-p "prompt"` — inline prompt (mutually exclusive with `-f`)
- `-f prompt-file.txt` — read prompt from file
- `-d dir` — working directory (default: current directory)
- `-o format` — `text`, `json`, or `stream-json` (default: `text`)
- `-m model` — model name
- `--mode mode` — `agent`, `plan`, or `ask`
- `--force` — allow file modifications (default)
- `--no-force` — do not modify files; agent only proposes changes
- `--stream` — use `--stream-partial-output` (implies `stream-json`); requires `jq` for progress display

**Examples:**

```bash
# Task from file, apply changes (default), text output
./scripts/run-task.sh -f tasks/refactor-auth.txt

# Inline prompt, specific project, JSON result
./scripts/run-task.sh -p "Summarize README.md" -d /path/to/repo -o json

# Stream with live progress
./scripts/run-task.sh -f tasks/review.txt -o stream-json --stream
```

## Error handling

- **Exit code**: Non-zero means the run failed; check stderr for the error message.
- **JSON output**: On failure, no well-formed JSON is emitted; only stderr.
- In scripts, always check `$?` after running `agent` or the wrapper and exit accordingly.

## Working directory

The headless agent uses the process **cwd** as the project root. Either:

- `cd /path/to/project && agent -p --force "..."`, or
- Use `scripts/run-task.sh -d /path/to/project ...`

## Additional resources

- For detailed output schemas and event types: [reference.md](reference.md)
- Official docs: [Using Headless CLI](https://cursor.com/docs/cli/headless), [Output format](https://cursor.com/docs/cli/reference/output-format)
