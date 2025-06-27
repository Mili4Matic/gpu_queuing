#!/usr/bin/env bash
# queue_cli.sh — tiny helper for queue UX
set -euo pipefail
ROOT="./dam/queue_jobs"; RUNTIME="$ROOT/runtime"; QUEUE="$RUNTIME/queue_state.txt"

CMD=${1:-ls}; ID=${2:-}

case $CMD in
  ls)
    echo "=== QUEUE ==="
    if [ -s "$QUEUE" ]; then nl -ba "$QUEUE"; else echo "(empty)"; fi
    echo -e "\n=== RUNNING ==="
    any=0
    for f in "$RUNTIME"/*.ready; do
      [ -e "$f" ] || continue
      jid=$(basename "$f" .ready); g=$(<"$f")
      echo "$jid → [$g]"; any=1
    done
    [ $any -eq 0 ] && echo "(none)"
    ;;
  info)
    [ -z "$ID" ] && { echo "usage: queue_cli.sh info JOB_ID"; exit 1; }
    grep "^${ID}:" "$QUEUE" || true
    [ -f "$RUNTIME/${ID}.ready" ] && echo "$ID is RUNNING"
    ;;
  cancel)
    [ -z "$ID" ] && { echo "usage: queue_cli.sh cancel JOB_ID"; exit 1; }
    sed -i "/^${ID}:/d" "$QUEUE" 2>/dev/null || true
    rm -f "$RUNTIME/${ID}.ready" 2>/dev/null || true
    echo "🗑️ cancelled $ID (if it existed)"
    ;;
  *)
    echo "usage: queue_cli.sh [ls|info|cancel] [JOB_ID]"; exit 1 ;;
esac
