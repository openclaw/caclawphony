#!/usr/bin/env bash
# test-gateway.sh — Run a PR worktree build as an isolated gateway instance
#
# Usage:
#   test-gateway.sh start <worktree-path> [--port PORT] [--config-dir DIR]
#   test-gateway.sh stop
#   test-gateway.sh status
#   test-gateway.sh call <method> [--params JSON]
#
# Starts the PR build on an alternate port (default 18790) alongside the
# production gateway. No plist juggling, no config mutation. Ctrl-C or
# `test-gateway.sh stop` to tear down.
#
# Environment:
#   TEST_GW_PORT       Override default port (18790)
#   TEST_GW_CONFIG_DIR Override config directory (default: ~/.openclaw)
#   TEST_GW_LOG        Log file path (default: /tmp/test-gateway.log)

set -euo pipefail

DEFAULT_PORT=18790
PIDFILE="/tmp/test-gateway.pid"
LOGFILE="${TEST_GW_LOG:-/tmp/test-gateway.log}"

die() { echo "ERROR: $*" >&2; exit 1; }

cmd_start() {
  local worktree=""
  local port="${TEST_GW_PORT:-$DEFAULT_PORT}"
  local config_dir="${TEST_GW_CONFIG_DIR:-$HOME/.openclaw}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port)  port="$2"; shift 2 ;;
      --config-dir) config_dir="$2"; shift 2 ;;
      *)
        if [[ -z "$worktree" ]]; then
          worktree="$1"; shift
        else
          die "Unknown argument: $1"
        fi
        ;;
    esac
  done

  [[ -n "$worktree" ]] || die "Usage: test-gateway.sh start <worktree-path>"
  [[ -d "$worktree" ]] || die "Worktree not found: $worktree"
  [[ -f "$worktree/dist/index.js" ]] || die "No build found at $worktree/dist/index.js — run pnpm build first"

  # Check for existing test gateway
  if [[ -f "$PIDFILE" ]]; then
    local old_pid
    old_pid=$(cat "$PIDFILE")
    if kill -0 "$old_pid" 2>/dev/null; then
      die "Test gateway already running (PID $old_pid). Run 'test-gateway.sh stop' first."
    fi
    rm -f "$PIDFILE"
  fi

  # Check port availability
  if lsof -i ":$port" -sTCP:LISTEN >/dev/null 2>&1; then
    die "Port $port already in use"
  fi

  echo "Starting test gateway..."
  echo "  Worktree: $worktree"
  echo "  Port:     $port"
  echo "  Config:   $config_dir"
  echo "  Log:      $LOGFILE"

  # Start gateway in background
  OPENCLAW_DATA_DIR="$config_dir" \
    node "$worktree/dist/index.js" gateway \
      --port "$port" \
      --bind localhost \
    > "$LOGFILE" 2>&1 &

  local pid=$!
  echo "$pid" > "$PIDFILE"

  # Wait for healthcheck
  echo -n "Waiting for gateway to be ready"
  local attempts=0
  local max_attempts=30
  while (( attempts < max_attempts )); do
    if curl -sf "http://127.0.0.1:$port/healthz" >/dev/null 2>&1; then
      echo " ✓"
      echo "Test gateway running on port $port (PID $pid)"
      echo ""
      echo "Usage:"
      echo "  export TEST_GW_PORT=$port"
      echo "  test-gateway.sh call sessions.list"
      echo "  test-gateway.sh stop"
      return 0
    fi
    echo -n "."
    sleep 1
    (( attempts++ ))

    # Check process is still alive
    if ! kill -0 "$pid" 2>/dev/null; then
      echo " ✗"
      echo "Gateway process died. Last 20 lines of log:"
      tail -20 "$LOGFILE"
      rm -f "$PIDFILE"
      return 1
    fi
  done

  echo " ✗ (timeout)"
  echo "Gateway didn't respond after ${max_attempts}s. Log tail:"
  tail -20 "$LOGFILE"
  kill "$pid" 2>/dev/null || true
  rm -f "$PIDFILE"
  return 1
}

cmd_stop() {
  if [[ ! -f "$PIDFILE" ]]; then
    echo "No test gateway running."
    return 0
  fi

  local pid
  pid=$(cat "$PIDFILE")

  if kill -0 "$pid" 2>/dev/null; then
    echo "Stopping test gateway (PID $pid)..."
    kill "$pid"
    # Wait for graceful shutdown
    local attempts=0
    while (( attempts < 10 )); do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 0.5
      (( attempts++ ))
    done
    # Force kill if still alive
    if kill -0 "$pid" 2>/dev/null; then
      echo "Force killing..."
      kill -9 "$pid" 2>/dev/null || true
    fi
    echo "Stopped."
  else
    echo "Process $pid not running (stale pidfile)."
  fi

  rm -f "$PIDFILE"
}

cmd_status() {
  local port="${TEST_GW_PORT:-$DEFAULT_PORT}"

  if [[ ! -f "$PIDFILE" ]]; then
    echo "No test gateway running."
    return 1
  fi

  local pid
  pid=$(cat "$PIDFILE")

  if kill -0 "$pid" 2>/dev/null; then
    echo "Test gateway running (PID $pid, port $port)"
    if curl -sf "http://127.0.0.1:$port/healthz" >/dev/null 2>&1; then
      echo "Health: OK"
    else
      echo "Health: UNREACHABLE"
    fi
  else
    echo "Stale pidfile (PID $pid not running)"
    rm -f "$PIDFILE"
    return 1
  fi
}

cmd_call() {
  local port="${TEST_GW_PORT:-$DEFAULT_PORT}"
  local method="$1"; shift
  local params='{}'

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --params) params="$2"; shift 2 ;;
      --json)   shift ;; # compat, always JSON
      *)        die "Unknown argument: $1" ;;
    esac
  done

  curl -sf "http://127.0.0.1:$port/api" \
    -H 'Content-Type: application/json' \
    -d "{\"method\": \"$method\", \"params\": $params}"
}

# Main dispatch
case "${1:-}" in
  start)  shift; cmd_start "$@" ;;
  stop)   cmd_stop ;;
  status) cmd_status ;;
  call)   shift; cmd_call "$@" ;;
  *)      echo "Usage: test-gateway.sh {start|stop|status|call} [args]"; exit 1 ;;
esac
