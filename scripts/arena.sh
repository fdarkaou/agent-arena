#!/usr/bin/env bash
# ============================================================================
# 🏟️ Agent Arena — Pit two AI coding agents against each other
# https://github.com/fdarkaou/agent-arena
#
# Usage: arena.sh "task prompt" [options]
# ============================================================================
set -euo pipefail

# ── Version ──────────────────────────────────────────────────────────────────
VERSION="1.0.0"

# ── Colors & Formatting ─────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Defaults ─────────────────────────────────────────────────────────────────
MODEL_A="claude"
MODEL_B="codex"
JUDGE_MODEL="claude"
TIMEOUT=600
OUTPUT_FORMAT="markdown"
REPO_DIR=""
NO_JUDGE=false
SAVE_RESULTS=""
SAVE_CODE=false
TASK=""
ARENA_DIR=""
WORKTREE_A=""
WORKTREE_B=""
TMUX_SESSION_A=""
TMUX_SESSION_B=""
PID_A=""
PID_B=""

# ── Helpers ──────────────────────────────────────────────────────────────────

usage() {
    cat <<'EOF'
🏟️ Agent Arena v${VERSION}

Usage: arena.sh <task> [options]

Arguments:
  <task>                Task prompt for both agents (required)

Options:
  --model-a <model>     First agent model (default: claude)
  --model-b <model>     Second agent model (default: codex)
  --judge <model>       Judge model (default: claude)
  --repo <path>         Repository to work in (default: current directory)
  --timeout <seconds>   Time limit per agent (default: 600)
  --output <format>     Output format: markdown or json (default: markdown)
  --no-judge            Skip judging, just show diffs
  --save <file>         Save results to file
  --save-code           Keep generated code (don't clean up worktrees)
  --version             Show version
  --help                Show this help

Models:
  claude                Uses 'claude' CLI (Anthropic — whatever model you have configured)
  codex                 Uses 'codex' CLI with --full-auto (OpenAI)
  opus, sonnet, haiku   Uses 'claude' CLI with --model flag
  gpt-4o, o3, o4-mini   Uses 'codex' CLI with --model flag

Examples:
  arena.sh "Build a REST API for todos with CRUD endpoints"
  arena.sh "Build auth middleware" --model-a opus --model-b codex
  arena.sh "Add rate limiting" --judge sonnet --timeout 300
  arena.sh "Build a CLI tool" --no-judge --save-code
EOF
    exit 0
}

log() { echo -e "${DIM}[arena]${RESET} $*"; }
log_ok() { echo -e "${GREEN}✓${RESET} $*"; }
log_warn() { echo -e "${YELLOW}⚠${RESET} $*"; }
log_err() { echo -e "${RED}✗${RESET} $*" >&2; }
log_step() { echo -e "\n${BOLD}${CYAN}▸ $*${RESET}"; }

die() { log_err "$@"; cleanup; exit 1; }

cleanup() {
    # Kill tmux sessions if they exist
    [[ -n "$TMUX_SESSION_A" ]] && tmux kill-session -t "$TMUX_SESSION_A" 2>/dev/null || true
    [[ -n "$TMUX_SESSION_B" ]] && tmux kill-session -t "$TMUX_SESSION_B" 2>/dev/null || true

    # Remove worktrees unless --save-code
    if [[ "$SAVE_CODE" == false && -n "$ARENA_DIR" ]]; then
        if [[ -n "$WORKTREE_A" && -d "$WORKTREE_A" ]]; then
            git -C "$REPO_DIR" worktree remove --force "$WORKTREE_A" 2>/dev/null || rm -rf "$WORKTREE_A"
        fi
        if [[ -n "$WORKTREE_B" && -d "$WORKTREE_B" ]]; then
            git -C "$REPO_DIR" worktree remove --force "$WORKTREE_B" 2>/dev/null || rm -rf "$WORKTREE_B"
        fi
        # Clean up arena branches
        git -C "$REPO_DIR" branch -D "arena/agent-a-$$" 2>/dev/null || true
        git -C "$REPO_DIR" branch -D "arena/agent-b-$$" 2>/dev/null || true
        # Remove arena temp dir
        rm -rf "$ARENA_DIR"
    elif [[ "$SAVE_CODE" == true && -n "$ARENA_DIR" ]]; then
        log "Code preserved in:"
        [[ -n "$WORKTREE_A" ]] && log "  Agent A: $WORKTREE_A"
        [[ -n "$WORKTREE_B" ]] && log "  Agent B: $WORKTREE_B"
    fi
}

trap cleanup EXIT INT TERM

# ── Parse Arguments ──────────────────────────────────────────────────────────
[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model-a)   MODEL_A="${2:?--model-a requires a value}"; shift 2 ;;
        --model-b)   MODEL_B="${2:?--model-b requires a value}"; shift 2 ;;
        --judge)     JUDGE_MODEL="${2:?--judge requires a value}"; shift 2 ;;
        --repo)      REPO_DIR="${2:?--repo requires a value}"; shift 2 ;;
        --timeout)   TIMEOUT="${2:?--timeout requires a value}"; shift 2 ;;
        --output)    OUTPUT_FORMAT="${2:?--output requires a value}"; shift 2 ;;
        --no-judge)  NO_JUDGE=true; shift ;;
        --save)      SAVE_RESULTS="${2:?--save requires a value}"; shift 2 ;;
        --save-code) SAVE_CODE=true; shift ;;
        --version)   echo "Agent Arena v${VERSION}"; exit 0 ;;
        --help|-h)   usage ;;
        -*)          die "Unknown option: $1" ;;
        *)
            if [[ -z "$TASK" ]]; then
                TASK="$1"
            else
                die "Unexpected argument: $1"
            fi
            shift ;;
    esac
done

[[ -z "$TASK" ]] && die "No task provided. Usage: arena.sh \"<task>\" [options]"

# ── Resolve repo directory ───────────────────────────────────────────────────
if [[ -z "$REPO_DIR" ]]; then
    REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
REPO_DIR="$(cd "$REPO_DIR" && pwd)"

# Verify it's a git repo
git -C "$REPO_DIR" rev-parse --git-dir &>/dev/null || die "Not a git repository: $REPO_DIR"

# Get the current branch / base ref
BASE_REF="$(git -C "$REPO_DIR" symbolic-ref --short HEAD 2>/dev/null || git -C "$REPO_DIR" rev-parse --short HEAD)"

# ── Check Dependencies ──────────────────────────────────────────────────────
check_cli() {
    local model="$1"
    local cli
    cli="$(resolve_cli "$model")"
    if ! command -v "$cli" &>/dev/null; then
        die "Required CLI '$cli' not found for model '$model'. Install it first."
    fi
}

resolve_cli() {
    local model="$1"
    case "$model" in
        claude|opus|sonnet|haiku|claude-*)  echo "claude" ;;
        codex|gpt-*|o3|o4-mini|o4-mini-*|codex-*) echo "codex" ;;
        *)
            # Default heuristic: if it contains "gpt" or "o3/o4", use codex; otherwise claude
            if [[ "$model" =~ ^(gpt|o[0-9]) ]]; then
                echo "codex"
            else
                echo "claude"
            fi
            ;;
    esac
}

resolve_model_flag() {
    local model="$1"
    case "$model" in
        claude|codex)  echo "" ;;  # Use default
        opus)          echo "claude-sonnet-4-20250514" ;;  # placeholder — claude CLI picks
        sonnet)        echo "claude-sonnet-4-20250514" ;;
        haiku)         echo "claude-haiku-4-20250514" ;;
        *)             echo "$model" ;;
    esac
}

model_display_name() {
    local model="$1"
    case "$model" in
        claude)  echo "Claude (default)" ;;
        codex)   echo "Codex (default)" ;;
        opus)    echo "Claude Opus" ;;
        sonnet)  echo "Claude Sonnet" ;;
        haiku)   echo "Claude Haiku" ;;
        *)       echo "$model" ;;
    esac
}

command -v git &>/dev/null || die "git is required"
command -v tmux &>/dev/null || die "tmux is required"
check_cli "$MODEL_A"
check_cli "$MODEL_B"
if [[ "$NO_JUDGE" == false ]]; then
    check_cli "$JUDGE_MODEL"
fi

# ── Setup Arena ──────────────────────────────────────────────────────────────
ARENA_TS="$(date +%Y%m%d-%H%M%S)"
ARENA_DIR="/tmp/agent-arena-${ARENA_TS}-$$"
mkdir -p "$ARENA_DIR"

BRANCH_A="arena/agent-a-$$"
BRANCH_B="arena/agent-b-$$"
WORKTREE_A="$ARENA_DIR/agent-a"
WORKTREE_B="$ARENA_DIR/agent-b"
TMUX_SESSION_A="arena-a-$$"
TMUX_SESSION_B="arena-b-$$"

NAME_A="$(model_display_name "$MODEL_A")"
NAME_B="$(model_display_name "$MODEL_B")"

echo ""
echo -e "${BOLD}${MAGENTA}🏟️  AGENT ARENA${RESET}"
echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Task:${RESET}    ${TASK}"
echo -e "${BOLD}Agent A:${RESET} ${CYAN}${NAME_A}${RESET}"
echo -e "${BOLD}Agent B:${RESET} ${YELLOW}${NAME_B}${RESET}"
echo -e "${BOLD}Judge:${RESET}   $(model_display_name "$JUDGE_MODEL")"
echo -e "${BOLD}Timeout:${RESET} ${TIMEOUT}s per agent"
echo -e "${BOLD}Repo:${RESET}    ${REPO_DIR}"
echo -e "${BOLD}Base:${RESET}    ${BASE_REF}"
echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ── Create Worktrees ─────────────────────────────────────────────────────────
log_step "Creating isolated worktrees..."

git -C "$REPO_DIR" worktree add -b "$BRANCH_A" "$WORKTREE_A" HEAD 2>/dev/null || \
    die "Failed to create worktree for Agent A"
log_ok "Agent A worktree: $WORKTREE_A"

git -C "$REPO_DIR" worktree add -b "$BRANCH_B" "$WORKTREE_B" HEAD 2>/dev/null || \
    die "Failed to create worktree for Agent B"
log_ok "Agent B worktree: $WORKTREE_B"

# ── Build Agent Commands ─────────────────────────────────────────────────────
build_agent_cmd() {
    local model="$1"
    local worktree="$2"
    local cli model_flag

    cli="$(resolve_cli "$model")"
    model_flag="$(resolve_model_flag "$model")"

    case "$cli" in
        claude)
            local cmd="cd '$worktree' && claude --print --dangerously-skip-permissions"
            if [[ -n "$model_flag" ]]; then
                cmd="$cmd --model '$model_flag'"
            fi
            cmd="$cmd '$TASK'"
            echo "$cmd"
            ;;
        codex)
            local cmd="cd '$worktree' && codex --full-auto --quiet"
            if [[ -n "$model_flag" ]]; then
                cmd="$cmd --model '$model_flag'"
            fi
            cmd="$cmd '$TASK'"
            echo "$cmd"
            ;;
    esac
}

CMD_A="$(build_agent_cmd "$MODEL_A" "$WORKTREE_A")"
CMD_B="$(build_agent_cmd "$MODEL_B" "$WORKTREE_B")"

# ── Run Agents in Parallel ───────────────────────────────────────────────────
log_step "Launching agents in parallel via tmux..."

# Agent A
tmux new-session -d -s "$TMUX_SESSION_A" -x 200 -y 50 \
    "bash -c '${CMD_A}; echo \"\nEXIT_CODE=\$?\" > \"$ARENA_DIR/status-a.txt\"; echo DONE' 2>&1 | tee '$ARENA_DIR/output-a.log'"
log_ok "Agent A running in tmux session: ${TMUX_SESSION_A}"

# Agent B
tmux new-session -d -s "$TMUX_SESSION_B" -x 200 -y 50 \
    "bash -c '${CMD_B}; echo \"\nEXIT_CODE=\$?\" > \"$ARENA_DIR/status-b.txt\"; echo DONE' 2>&1 | tee '$ARENA_DIR/output-b.log'"
log_ok "Agent B running in tmux session: ${TMUX_SESSION_B}"

echo ""
log "Watch live:  ${DIM}tmux attach -t ${TMUX_SESSION_A}${RESET}  or  ${DIM}tmux attach -t ${TMUX_SESSION_B}${RESET}"
echo ""

# ── Wait for Both Agents ─────────────────────────────────────────────────────
log_step "Waiting for agents to finish (timeout: ${TIMEOUT}s)..."

wait_for_agent() {
    local session="$1"
    local label="$2"
    local status_file="$3"
    local elapsed=0

    while [[ $elapsed -lt $TIMEOUT ]]; do
        # Check if tmux session still exists
        if ! tmux has-session -t "$session" 2>/dev/null; then
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))

        # Progress indicator every 30s
        if (( elapsed % 30 == 0 )); then
            log "${label}: ${elapsed}s elapsed..."
        fi
    done

    # If still running after timeout, kill it
    if tmux has-session -t "$session" 2>/dev/null; then
        log_warn "${label}: Timed out after ${TIMEOUT}s — killing"
        tmux kill-session -t "$session" 2>/dev/null || true
        echo "EXIT_CODE=124" > "$status_file"
        return 124
    fi

    return 0
}

# Wait for both in parallel
wait_for_agent "$TMUX_SESSION_A" "Agent A" "$ARENA_DIR/status-a.txt" &
WAIT_PID_A=$!

wait_for_agent "$TMUX_SESSION_B" "Agent B" "$ARENA_DIR/status-b.txt" &
WAIT_PID_B=$!

# Wait for both waiters
STATUS_A=0
STATUS_B=0
wait $WAIT_PID_A || STATUS_A=$?
wait $WAIT_PID_B || STATUS_B=$?

# Clear the tmux session vars so cleanup doesn't try to kill them again
TMUX_SESSION_A=""
TMUX_SESSION_B=""

log_ok "Both agents finished"

# ── Collect Diffs ────────────────────────────────────────────────────────────
log_step "Collecting diffs..."

# Stage all changes in each worktree so we capture new files
(cd "$WORKTREE_A" && git add -A && git diff --cached --stat) > "$ARENA_DIR/stat-a.txt" 2>/dev/null || true
(cd "$WORKTREE_B" && git add -A && git diff --cached --stat) > "$ARENA_DIR/stat-b.txt" 2>/dev/null || true

DIFF_A="$(cd "$WORKTREE_A" && git add -A && git diff --cached 2>/dev/null || echo '(no changes)')"
DIFF_B="$(cd "$WORKTREE_B" && git add -A && git diff --cached 2>/dev/null || echo '(no changes)')"

# Truncate huge diffs for the judge (keep first 15000 chars)
MAX_DIFF=15000
if [[ ${#DIFF_A} -gt $MAX_DIFF ]]; then
    DIFF_A="${DIFF_A:0:$MAX_DIFF}
... [truncated — ${#DIFF_A} chars total]"
fi
if [[ ${#DIFF_B} -gt $MAX_DIFF ]]; then
    DIFF_B="${DIFF_B:0:$MAX_DIFF}
... [truncated — ${#DIFF_B} chars total]"
fi

LINES_A=$(echo "$DIFF_A" | wc -l)
LINES_B=$(echo "$DIFF_B" | wc -l)
log_ok "Agent A diff: ${LINES_A} lines"
log_ok "Agent B diff: ${LINES_B} lines"

# Check for empty diffs
if [[ "$DIFF_A" == "(no changes)" && "$DIFF_B" == "(no changes)" ]]; then
    die "Both agents produced no changes. Nothing to compare."
fi

# ── Judge ────────────────────────────────────────────────────────────────────
if [[ "$NO_JUDGE" == true ]]; then
    log_step "Skipping judge (--no-judge)"
    echo ""
    echo -e "${BOLD}═══ Agent A Diff (${NAME_A}) ═══${RESET}"
    echo "$DIFF_A"
    echo ""
    echo -e "${BOLD}═══ Agent B Diff (${NAME_B}) ═══${RESET}"
    echo "$DIFF_B"
    exit 0
fi

log_step "Sending to judge: $(model_display_name "$JUDGE_MODEL")..."

JUDGE_PROMPT="You are an expert code reviewer acting as a judge in a coding competition.

## Task Given to Both Agents
${TASK}

## Agent A Output (${NAME_A})
\`\`\`diff
${DIFF_A}
\`\`\`

## Agent B Output (${NAME_B})
\`\`\`diff
${DIFF_B}
\`\`\`

## Your Job
Evaluate BOTH outputs on these criteria. Score each 0-10:

1. **Correctness**: Does it work? Edge cases handled?
2. **Code Quality**: Clean, readable, well-structured?
3. **Simplicity**: Elegant, not over-engineered?
4. **Completeness**: Fully solves the task?
5. **Best Practices**: Error handling, types, security, tests?

## Required Output Format
You MUST respond in EXACTLY this format (no deviations):

SCORES_START
correctness_a: <0-10>
correctness_b: <0-10>
quality_a: <0-10>
quality_b: <0-10>
simplicity_a: <0-10>
simplicity_b: <0-10>
completeness_a: <0-10>
completeness_b: <0-10>
practices_a: <0-10>
practices_b: <0-10>
SCORES_END

NOTES_START
- <your first observation comparing the two>
- <your second observation>
- <your third observation>
- <any more observations>
NOTES_END

Be fair, specific, and decisive. There must be a winner (no ties unless truly identical)."

# Write judge prompt to file (avoids shell escaping nightmares)
echo "$JUDGE_PROMPT" > "$ARENA_DIR/judge-prompt.txt"

# Run judge
JUDGE_CLI="$(resolve_cli "$JUDGE_MODEL")"
JUDGE_MODEL_FLAG="$(resolve_model_flag "$JUDGE_MODEL")"

JUDGE_OUTPUT=""
case "$JUDGE_CLI" in
    claude)
        JUDGE_CMD="claude --print"
        if [[ -n "$JUDGE_MODEL_FLAG" ]]; then
            JUDGE_CMD="$JUDGE_CMD --model '$JUDGE_MODEL_FLAG'"
        fi
        JUDGE_OUTPUT="$(eval "$JUDGE_CMD" < "$ARENA_DIR/judge-prompt.txt" 2>/dev/null)" || {
            log_warn "Judge failed, trying without model flag..."
            JUDGE_OUTPUT="$(claude --print < "$ARENA_DIR/judge-prompt.txt" 2>/dev/null)" || die "Judge failed"
        }
        ;;
    codex)
        JUDGE_CMD="codex --full-auto --quiet"
        if [[ -n "$JUDGE_MODEL_FLAG" ]]; then
            JUDGE_CMD="$JUDGE_CMD --model '$JUDGE_MODEL_FLAG'"
        fi
        JUDGE_OUTPUT="$(eval "$JUDGE_CMD" "'$(cat "$ARENA_DIR/judge-prompt.txt")'" 2>/dev/null)" || die "Judge (codex) failed"
        ;;
esac

echo "$JUDGE_OUTPUT" > "$ARENA_DIR/judge-output.txt"
log_ok "Judge complete"

# ── Parse Scores ─────────────────────────────────────────────────────────────
parse_score() {
    local key="$1"
    echo "$JUDGE_OUTPUT" | sed -n "/SCORES_START/,/SCORES_END/p" | grep "^${key}:" | awk '{print $2}' | tr -d ' '
}

CORRECTNESS_A=$(parse_score "correctness_a")
CORRECTNESS_B=$(parse_score "correctness_b")
QUALITY_A=$(parse_score "quality_a")
QUALITY_B=$(parse_score "quality_b")
SIMPLICITY_A=$(parse_score "simplicity_a")
SIMPLICITY_B=$(parse_score "simplicity_b")
COMPLETENESS_A=$(parse_score "completeness_a")
COMPLETENESS_B=$(parse_score "completeness_b")
PRACTICES_A=$(parse_score "practices_a")
PRACTICES_B=$(parse_score "practices_b")

# Default to 0 if parsing failed
CORRECTNESS_A=${CORRECTNESS_A:-0}; CORRECTNESS_B=${CORRECTNESS_B:-0}
QUALITY_A=${QUALITY_A:-0}; QUALITY_B=${QUALITY_B:-0}
SIMPLICITY_A=${SIMPLICITY_A:-0}; SIMPLICITY_B=${SIMPLICITY_B:-0}
COMPLETENESS_A=${COMPLETENESS_A:-0}; COMPLETENESS_B=${COMPLETENESS_B:-0}
PRACTICES_A=${PRACTICES_A:-0}; PRACTICES_B=${PRACTICES_B:-0}

TOTAL_A=$((CORRECTNESS_A + QUALITY_A + SIMPLICITY_A + COMPLETENESS_A + PRACTICES_A))
TOTAL_B=$((CORRECTNESS_B + QUALITY_B + SIMPLICITY_B + COMPLETENESS_B + PRACTICES_B))

# Parse notes
NOTES="$(echo "$JUDGE_OUTPUT" | sed -n '/NOTES_START/,/NOTES_END/{/NOTES_START/d;/NOTES_END/d;p}')"

# Determine winner
WINNER=""
if [[ $TOTAL_A -gt $TOTAL_B ]]; then
    WINNER="🅰️ ${NAME_A}"
elif [[ $TOTAL_B -gt $TOTAL_A ]]; then
    WINNER="🅱️ ${NAME_B}"
else
    WINNER="🤝 Tie"
fi

# ── Format Output ────────────────────────────────────────────────────────────
ARENA_DATE="$(date -u '+%Y-%m-%d %H:%M UTC')"

format_markdown() {
    cat <<EOF

🏟️ AGENT ARENA — Results
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Task: "${TASK}"
Date: ${ARENA_DATE}

🅰️ ${NAME_A}     vs     🅱️ ${NAME_B}

         Correctness:   ${CORRECTNESS_A}/10         ${CORRECTNESS_B}/10
        Code Quality:   ${QUALITY_A}/10         ${QUALITY_B}/10
          Simplicity:   ${SIMPLICITY_A}/10         ${SIMPLICITY_B}/10
       Completeness:   ${COMPLETENESS_A}/10         ${COMPLETENESS_B}/10
     Best Practices:   ${PRACTICES_A}/10         ${PRACTICES_B}/10
         ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              TOTAL:  ${TOTAL_A}/50        ${TOTAL_B}/50

🏆 Winner: ${WINNER}

Judge Notes:
${NOTES}
EOF
}

format_json() {
    cat <<EOF
{
  "task": $(echo "$TASK" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'),
  "date": "${ARENA_DATE}",
  "agent_a": {
    "model": "${MODEL_A}",
    "name": "${NAME_A}",
    "scores": {
      "correctness": ${CORRECTNESS_A},
      "code_quality": ${QUALITY_A},
      "simplicity": ${SIMPLICITY_A},
      "completeness": ${COMPLETENESS_A},
      "best_practices": ${PRACTICES_A}
    },
    "total": ${TOTAL_A},
    "status": "$([ $STATUS_A -eq 0 ] && echo 'completed' || echo 'timeout')"
  },
  "agent_b": {
    "model": "${MODEL_B}",
    "name": "${NAME_B}",
    "scores": {
      "correctness": ${CORRECTNESS_B},
      "code_quality": ${QUALITY_B},
      "simplicity": ${SIMPLICITY_B},
      "completeness": ${COMPLETENESS_B},
      "best_practices": ${PRACTICES_B}
    },
    "total": ${TOTAL_B},
    "status": "$([ $STATUS_B -eq 0 ] && echo 'completed' || echo 'timeout')"
  },
  "winner": "$([ $TOTAL_A -gt $TOTAL_B ] && echo "${MODEL_A}" || ([ $TOTAL_B -gt $TOTAL_A ] && echo "${MODEL_B}" || echo "tie"))",
  "judge": "${JUDGE_MODEL}",
  "notes": $(echo "$NOTES" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')
}
EOF
}

# ── Output ───────────────────────────────────────────────────────────────────
RESULT=""
case "$OUTPUT_FORMAT" in
    markdown|md)  RESULT="$(format_markdown)" ;;
    json)         RESULT="$(format_json)" ;;
    *)            die "Unknown output format: $OUTPUT_FORMAT" ;;
esac

echo "$RESULT"

# Save results if requested
if [[ -n "$SAVE_RESULTS" ]]; then
    echo "$RESULT" > "$SAVE_RESULTS"
    log_ok "Results saved to: $SAVE_RESULTS"
fi

# Final summary
echo ""
log "Arena temp dir: $ARENA_DIR"
if [[ "$SAVE_CODE" == true ]]; then
    log "Agent code preserved (--save-code):"
    log "  Agent A: $WORKTREE_A"
    log "  Agent B: $WORKTREE_B"
fi

exit 0
