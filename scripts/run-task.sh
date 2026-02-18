#!/usr/bin/env bash
# Wrapper for Cursor CLI headless (agent -p). Supports prompt from stdin/file,
# output format, and optional stream progress. Requires: agent (Cursor CLI).
# For --stream progress display, jq is required.

set -euo pipefail

PROMPT=""
PROMPT_FILE=""
DIR=""
OUTPUT_FORMAT="text"
MODEL=""
MODE=""
FORCE=true
STREAM=true
DEBUG=false

usage() {
  cat <<'EOF'
Usage: run-task.sh -p "prompt" | -f prompt-file [options]

Prompt (exactly one):
  -p "prompt"       Inline prompt
  -f prompt-file    Read prompt from file

Options:
  -d dir            Working directory (default: cwd)
  -o format         Output format: text, json, stream-json (default: stream-json when streaming)
  -m model          Model name
  --mode mode       Mode: agent, plan, ask
  --force           Allow file modifications (default)
  --no-force        Do not modify files; agent only proposes changes
  --stream          Use stream-json with progress display (default; requires jq)
  --no-stream       Plain output only (text or json per -o); no progress display
  --debug           Show full raw NDJSON on stdout (verbose); default shows compact progress only

Examples:
  ./scripts/run-task.sh -f task.txt
  ./scripts/run-task.sh -p "Refactor utils.js" -d /path/to/project --no-stream -o json
  ./scripts/run-task.sh -f review.txt --debug
EOF
  exit 1
}

# Check agent is available
if ! command -v agent &>/dev/null; then
  echo "Error: 'agent' (Cursor CLI) not found on PATH. Install: curl https://cursor.com/install -fsS | bash" >&2
  exit 1
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p)
      [[ -n "$PROMPT_FILE" ]] && { echo "Error: use -p or -f, not both" >&2; usage; }
      PROMPT="${2:?Error: -p requires a prompt string}"
      shift 2
      ;;
    -f)
      [[ -n "$PROMPT" ]] && { echo "Error: use -p or -f, not both" >&2; usage; }
      PROMPT_FILE="${2:?Error: -f requires a file path}"
      shift 2
      ;;
    -d)
      DIR="${2:?Error: -d requires a directory}"
      shift 2
      ;;
    -o)
      OUTPUT_FORMAT="${2:?Error: -o requires format (text|json|stream-json)}"
      shift 2
      ;;
    -m)
      MODEL="${2:?Error: -m requires model name}"
      shift 2
      ;;
    --mode)
      MODE="${2:?Error: --mode requires agent|plan|ask}"
      shift 2
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --no-force)
      FORCE=false
      shift
      ;;
    --stream)
      STREAM=true
      shift
      ;;
    --no-stream)
      STREAM=false
      shift
      ;;
    --debug)
      DEBUG=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: unknown option $1" >&2
      usage
      ;;
  esac
done

# Require exactly one of -p or -f
if [[ -z "$PROMPT" && -z "$PROMPT_FILE" ]]; then
  echo "Error: provide -p \"prompt\" or -f prompt-file" >&2
  usage
fi
if [[ -n "$PROMPT" && -n "$PROMPT_FILE" ]]; then
  echo "Error: use -p or -f, not both" >&2
  usage
fi

# Resolve prompt
if [[ -n "$PROMPT_FILE" ]]; then
  if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "Error: prompt file not found: $PROMPT_FILE" >&2
    exit 1
  fi
  PROMPT=$(cat "$PROMPT_FILE")
fi

# --stream implies stream-json and requires jq for progress
if [[ "$STREAM" == true ]]; then
  OUTPUT_FORMAT="stream-json"
  if ! command -v jq &>/dev/null; then
    echo "Warning: --stream progress display requires jq; output will be raw NDJSON" >&2
  fi
fi

# Build agent command (array for safe quoting)
CMD=(agent -p)
[[ "$FORCE" == true ]] && CMD+=(--force)
CMD+=(--output-format "$OUTPUT_FORMAT")
[[ -n "$MODEL" ]] && CMD+=(-m "$MODEL")
[[ -n "$MODE" ]] && CMD+=(--mode "$MODE")
[[ "$STREAM" == true ]] && CMD+=(--stream-partial-output)

# Run from directory if set
run_agent() {
  if [[ -n "$DIR" ]]; then
    if [[ ! -d "$DIR" ]]; then
      echo "Error: directory not found: $DIR" >&2
      exit 1
    fi
    cd "$DIR" && "${CMD[@]}" "$PROMPT"
  else
    "${CMD[@]}" "$PROMPT"
  fi
}

# Debug stream: full raw NDJSON on stdout + verbose progress on stderr
stream_debug() {
  local have_jq=false
  command -v jq &>/dev/null && have_jq=true

  if [[ "$have_jq" != true ]]; then
    cat
    return
  fi

  local accumulated_text="" tool_count=0 start_time
  start_time=$(date +%s)

  while IFS= read -r line; do
    echo "$line"
    type=$(echo "$line" | jq -r '.type // empty')
    subtype=$(echo "$line" | jq -r '.subtype // empty')

    case "$type" in
      system)
        if [[ "$subtype" == "init" ]]; then
          model=$(echo "$line" | jq -r '.model // "unknown"')
          echo "[init] model: $model" >&2
        fi
        ;;
      assistant)
        content=$(echo "$line" | jq -r '.message.content[0].text // empty')
        accumulated_text="$accumulated_text$content"
        printf "\r[text] %d chars" ${#accumulated_text} >&2
        ;;
      tool_call)
        if [[ "$subtype" == "started" ]]; then
          tool_count=$((tool_count + 1))
          if echo "$line" | jq -e '.tool_call.writeToolCall' >/dev/null 2>&1; then
            path=$(echo "$line" | jq -r '.tool_call.writeToolCall.args.path // "unknown"')
            echo -e "\n[tool #$tool_count] Writing $path" >&2
          elif echo "$line" | jq -e '.tool_call.readToolCall' >/dev/null 2>&1; then
            path=$(echo "$line" | jq -r '.tool_call.readToolCall.args.path // "unknown"')
            echo -e "\n[tool #$tool_count] Reading $path" >&2
          fi
        elif [[ "$subtype" == "completed" ]]; then
          if echo "$line" | jq -e '.tool_call.writeToolCall.result.success' >/dev/null 2>&1; then
            wlines=$(echo "$line" | jq -r '.tool_call.writeToolCall.result.success.linesCreated // 0')
            size=$(echo "$line" | jq -r '.tool_call.writeToolCall.result.success.fileSize // 0')
            echo "   -> wrote $wlines lines ($size bytes)" >&2
          elif echo "$line" | jq -e '.tool_call.readToolCall.result.success' >/dev/null 2>&1; then
            rlines=$(echo "$line" | jq -r '.tool_call.readToolCall.result.success.totalLines // 0')
            echo "   -> read $rlines lines" >&2
          fi
        fi
        ;;
      result)
        duration=$(echo "$line" | jq -r '.duration_ms // 0')
        end_time=$(date +%s)
        total_time=$((end_time - start_time))
        echo -e "\n[done] ${duration}ms (${total_time}s wall), $tool_count tools, ${#accumulated_text} chars" >&2
        ;;
    esac
  done
}

# Default stream: compact progress on stderr, only final result text on stdout
stream_compact() {
  local have_jq=false
  command -v jq &>/dev/null && have_jq=true

  if [[ "$have_jq" != true ]]; then
    cat
    return
  fi

  local char_count=0 tool_count=0 start_time result_text=""
  start_time=$(date +%s)

  while IFS= read -r line; do
    type=$(echo "$line" | jq -r '.type // empty')
    subtype=$(echo "$line" | jq -r '.subtype // empty')

    case "$type" in
      system)
        if [[ "$subtype" == "init" ]]; then
          model=$(echo "$line" | jq -r '.model // "unknown"')
          echo "[init] model: $model" >&2
        fi
        ;;
      assistant)
        content=$(echo "$line" | jq -r '.message.content[0].text // empty')
        char_count=$((char_count + ${#content}))
        elapsed=$(( $(date +%s) - start_time ))
        printf "\r[progress] %d chars, %d tools, %ds elapsed" "$char_count" "$tool_count" "$elapsed" >&2
        ;;
      tool_call)
        if [[ "$subtype" == "started" ]]; then
          tool_count=$((tool_count + 1))
          if echo "$line" | jq -e '.tool_call.writeToolCall' >/dev/null 2>&1; then
            path=$(echo "$line" | jq -r '.tool_call.writeToolCall.args.path // "unknown"')
            echo -e "\n[tool #$tool_count] write $path" >&2
          elif echo "$line" | jq -e '.tool_call.readToolCall' >/dev/null 2>&1; then
            path=$(echo "$line" | jq -r '.tool_call.readToolCall.args.path // "unknown"')
            echo -e "\n[tool #$tool_count] read $path" >&2
          else
            echo -e "\n[tool #$tool_count] ..." >&2
          fi
        fi
        ;;
      result)
        duration=$(echo "$line" | jq -r '.duration_ms // 0')
        result_text=$(echo "$line" | jq -r '.result // empty')
        end_time=$(date +%s)
        total_time=$((end_time - start_time))
        echo -e "\n[done] ${duration}ms (${total_time}s wall), $tool_count tools, $char_count chars" >&2
        echo "$result_text"
        ;;
    esac
  done
}

# Execute and exit with agent's status
if [[ "$OUTPUT_FORMAT" == "stream-json" && "$STREAM" == true ]]; then
  if [[ "$DEBUG" == true ]]; then
    run_agent | stream_debug
  else
    run_agent | stream_compact
  fi
  exit "${PIPESTATUS[0]}"
else
  run_agent
  exit $?
fi
