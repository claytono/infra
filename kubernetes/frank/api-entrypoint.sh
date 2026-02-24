#!/bin/sh
trap 'kill 0; wait; exit 0' TERM INT

API_DIR="/home/node/.openclaw/workspace/www/games/api"
LOG_DIR="$API_DIR/logs"
LOG_FILE="$LOG_DIR/server.log"
RESTART_FILE="$API_DIR/.restart"
MAX_BYTES=1048576  # 1MB
KEEP=3

mkdir -p "$LOG_DIR"
: >> "$LOG_FILE"

# Background log rotator - checks every 60s
(while sleep 60; do
  size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$size" -gt "$MAX_BYTES" ]; then
    i=$KEEP
    while [ $i -gt 1 ]; do
      j=$((i - 1))
      [ -f "$LOG_FILE.$j" ] && mv "$LOG_FILE.$j" "$LOG_FILE.$i"
      i=$j
    done
    cp "$LOG_FILE" "$LOG_FILE.1" && : > "$LOG_FILE"
  fi
done) &

# Stream log to stdout for kubectl logs
tail -f "$LOG_FILE" &

cd "$API_DIR" || exit 1

# Main loop — restarts bun in-process to avoid CrashLoopBackOff.
while true; do
  rm -f "$RESTART_FILE"
  bun install >> "$LOG_FILE" 2>&1

  bun run --watch server.js >> "$LOG_FILE" 2>&1 &
  BUN_PID=$!

  # Wait for .restart trigger or bun exit
  while kill -0 "$BUN_PID" 2>/dev/null; do
    if [ -f "$RESTART_FILE" ]; then
      rm -f "$RESTART_FILE"
      echo "$(date -Iseconds) Restart triggered by .restart file" >> "$LOG_FILE"
      kill "$BUN_PID" 2>/dev/null
      wait "$BUN_PID" 2>/dev/null || true
      break
    fi
    sleep 2
  done

  echo "$(date -Iseconds) Restarting in 1s..." >> "$LOG_FILE"
  sleep 1
done
