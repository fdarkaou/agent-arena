<p align="center">
  <h1 align="center">🏟️ Agent Arena</h1>
  <p align="center">
    <strong>Pit two AI coding agents against each other. Automated benchmarks with a judge.</strong>
  </p>
  <p align="center">
    <a href="#quickstart">Quickstart</a> •
    <a href="#how-it-works">How It Works</a> •
    <a href="#cli-reference">CLI Reference</a> •
    <a href="#examples">Examples</a> •
    <a href="#judging">Judging</a>
  </p>
  <p align="center">
    <img src="https://img.shields.io/badge/claude-code-blueviolet?logo=anthropic" alt="Claude Code">
    <img src="https://img.shields.io/badge/codex-cli-green?logo=openai" alt="Codex CLI">
    <img src="https://img.shields.io/badge/openclaw-compatible-orange" alt="OpenClaw">
    <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License">
    <img src="https://img.shields.io/badge/bash-5.0%2B-lightgrey?logo=gnubash" alt="Bash">
  </p>
</p>

---

> **Claude vs Codex? Opus vs GPT? Stop debating — let them fight.**
>
> Agent Arena runs two AI coding agents on the same task in parallel, collects their output, and has a third AI judge score them on a structured rubric. Get a scorecard with a clear winner in minutes.

## Quickstart

```bash
# Clone
git clone https://github.com/fdarkaou/agent-arena.git
cd agent-arena

# Run your first arena match
./scripts/arena.sh "Build a REST API for todos with CRUD endpoints"
```

That's it. No config files. No setup. Good defaults out of the box.

## How It Works

```
┌─────────────────────────────────────────────────────┐
│                    AGENT ARENA                       │
│                                                      │
│  ┌──────────┐    Task Prompt    ┌──────────┐        │
│  │ Agent A   │◄────────────────►│ Agent B   │        │
│  │ (Claude)  │   git worktree   │ (Codex)   │        │
│  └─────┬─────┘   isolation     └─────┬─────┘        │
│        │                              │              │
│        ▼                              ▼              │
│     diff A                         diff B            │
│        │                              │              │
│        └──────────┐  ┌───────────────┘              │
│                   ▼  ▼                               │
│              ┌──────────┐                            │
│              │  Judge    │                            │
│              │ (Claude)  │                            │
│              └─────┬─────┘                           │
│                    ▼                                  │
│              📊 Scorecard                            │
└─────────────────────────────────────────────────────┘
```

1. **Two worktrees** — Each agent gets a clean git worktree (isolated, no conflicts)
2. **Parallel execution** — Both agents run simultaneously in tmux sessions (you can watch live!)
3. **Diff collection** — After both finish (or timeout), diffs are collected
4. **Structured judging** — A third agent scores both on 5 criteria (0–10 each)
5. **Scorecard** — Clear winner with detailed notes

## CLI Reference

```bash
arena.sh <task> [options]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<task>` | The coding task prompt (required, quoted string) |

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `--model-a <model>` | `claude` | First agent (uses `claude` CLI) |
| `--model-b <model>` | `codex` | Second agent (uses `codex` CLI) |
| `--judge <model>` | `claude` | Judge model |
| `--repo <path>` | current dir | Repository to work in |
| `--timeout <sec>` | `600` | Time limit per agent (seconds) |
| `--output <fmt>` | `markdown` | Output format: `markdown` or `json` |
| `--no-judge` | — | Skip judging, just show both diffs |
| `--save <file>` | — | Save scorecard to a file |
| `--save-code` | — | Keep worktrees (don't clean up) |
| `--help` | — | Show help |
| `--version` | — | Show version |

### Model Shortcuts

| Shortcut | CLI Used | Notes |
|----------|----------|-------|
| `claude` | `claude` | Your default Anthropic model |
| `codex` | `codex` | Your default OpenAI model |
| `opus` | `claude --model ...` | Claude Opus |
| `sonnet` | `claude --model ...` | Claude Sonnet |
| `haiku` | `claude --model ...` | Claude Haiku |
| `gpt-4o` | `codex --model ...` | GPT-4o |
| `o3` | `codex --model ...` | OpenAI o3 |
| Any string | Auto-detected | Full model IDs work too |

## Examples

### Basic: Claude vs Codex (defaults)

```bash
arena.sh "Build a REST API for todos with CRUD endpoints"
```

### Custom Models

```bash
arena.sh "Build auth middleware with JWT" --model-a opus --model-b codex
```

### Fast Match with Short Timeout

```bash
arena.sh "Write a function to validate email addresses" --timeout 120
```

### Save Everything

```bash
arena.sh "Build a snake game in Python" --save results.md --save-code
```

### JSON Output (for CI/automation)

```bash
arena.sh "Implement binary search" --output json | jq .winner
```

### No Judge — Just Compare

```bash
arena.sh "Refactor the auth module" --no-judge --save-code
```

### In a Specific Repo

```bash
arena.sh "Fix the failing tests" --repo ~/projects/my-app
```

## Judging

The judge evaluates both agents on **5 criteria** (0–10 each, **50 total**):

| Criteria | What It Measures |
|----------|-----------------|
| **Correctness** | Does it work? Edge cases handled? |
| **Code Quality** | Clean, readable, well-structured? |
| **Simplicity** | Elegant, not over-engineered? |
| **Completeness** | Fully solves the task? |
| **Best Practices** | Error handling, types, security, tests? |

### Sample Scorecard

```
🏟️ AGENT ARENA — Results
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Task: "Build a REST API for todos"
Date: 2026-02-11 19:30 UTC

🅰️ Claude (default)     vs     🅱️ Codex (default)

         Correctness:   8/10         7/10
        Code Quality:   9/10         8/10
          Simplicity:   7/10         9/10
       Completeness:   9/10         8/10
     Best Practices:   8/10         7/10
         ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              TOTAL:  41/50        39/50

🏆 Winner: 🅰️ Claude (default)

Judge Notes:
- Claude's solution included comprehensive error handling and input validation
- Codex was more concise but missed edge cases in the DELETE endpoint
- Both implemented clean project structure with proper separation of concerns
```

## Requirements

- **git** — for worktree isolation
- **tmux** — for parallel agent execution
- **claude CLI** — for Anthropic models ([install](https://docs.anthropic.com/en/docs/claude-code))
- **codex CLI** — for OpenAI models ([install](https://github.com/openai/codex))

## Installation

### As an OpenClaw Skill

```bash
# Clone into your skills directory
git clone https://github.com/fdarkaou/agent-arena.git \
  ~/clawd/agent/skills/agent-arena
```

### Standalone

```bash
git clone https://github.com/fdarkaou/agent-arena.git
cd agent-arena

# Add to PATH (optional)
ln -s "$(pwd)/scripts/arena.sh" /usr/local/bin/arena
```

## Tips

- **Watch live** — After launch, attach to tmux sessions to watch agents code in real-time
- **Start small** — Try simple tasks first (`"Write a fibonacci function"`) to test your setup
- **Save code** — Use `--save-code` to inspect what each agent actually wrote
- **JSON + jq** — Pipe JSON output to jq for scripting and automation
- **Different judges** — Try `--judge sonnet` for faster/cheaper judging

## FAQ

**Q: Can I use two Claude models against each other?**
A: Yes! Use `--model-a opus --model-b sonnet` — both use the `claude` CLI with different `--model` flags.

**Q: What if an agent crashes or times out?**
A: The arena handles it gracefully. The diff will be empty or partial, and the judge will score accordingly.

**Q: Does this cost money?**
A: Yes — each agent run and the judge evaluation use API calls. A typical match costs roughly the same as 3 normal agent interactions.

**Q: Can I use this in CI?**
A: Absolutely. Use `--output json` for machine-readable output and `--save` to persist results.

---

<p align="center">
  <sub>
    Built with ❤️ by <a href="https://buildfound.com"><strong>BuildFound</strong></a> — powering <a href="https://genviral.io"><strong>GenViral</strong></a>
    <br>
    An <a href="https://github.com/nichochar/open-claw">OpenClaw</a> skill
  </sub>
</p>
