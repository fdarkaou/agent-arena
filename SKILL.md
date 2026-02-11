# Agent Arena

**Pit two AI coding agents against each other on the same task, with automated judging.**

## What It Does

Runs two AI agents (e.g., Claude vs Codex) on the same coding task in parallel using isolated git worktrees, then has a third agent judge both outputs on a structured rubric.

## Usage

```bash
# Basic — uses claude vs codex with defaults
arena.sh "Build a REST API for todos with CRUD endpoints"

# Custom models
arena.sh "Build auth middleware" --model-a opus --model-b codex

# With custom judge and timeout
arena.sh "Add rate limiting" --judge sonnet --timeout 300

# Skip judging
arena.sh "Build a CLI tool" --no-judge

# Save everything
arena.sh "Build a snake game" --save results.md --save-code

# JSON output
arena.sh "Build a chat app" --output json
```

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--model-a` | `claude` | First agent model |
| `--model-b` | `codex` | Second agent model |
| `--judge` | `claude` | Judge model |
| `--repo` | `.` | Repository to work in |
| `--timeout` | `600` | Seconds per agent |
| `--output` | `markdown` | Output format (markdown/json) |
| `--no-judge` | off | Skip judging, show diffs only |
| `--save` | – | Save results to file |
| `--save-code` | off | Keep worktrees after run |

## Requirements

- `git`, `tmux`
- `claude` CLI (for Anthropic models)
- `codex` CLI (for OpenAI models)

## Script Location

`scripts/arena.sh`
