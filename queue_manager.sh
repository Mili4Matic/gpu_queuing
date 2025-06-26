#!/usr/bin/env bash
# queue_manager.sh — priority FIFO scheduler + watchdog + startup-recovery
set -euo pipefail

# ------------ paths & settings ------------------------------------------------
QUEUE_ROOT="./dam/queue_jobs"
RUNTIME="$QUEUE_ROOT/runtime"
LOCK="$RUNTIME/.manager.lock"
QUEUE_FILE="$RUNTIME/queue_state.txt"
GPU_STATUS="$RUNTIME/gpu_status.json"

STALE_MINUTES=2   # .ready sin latido ≥ 2 min  → limpieza
SLEEP_IDLE=5      # seg. entre barridos si la cola está vacía
# ------------------------------------------------------------------------------

mkdir -p "$RUNTIME"
[ -e "$LOCK" ] && { echo "❌ manager already running"; exit 1; }
touch "$LOCK"; trap 'rm -f "$LOCK"; exit 0' SIGINT SIGTERM EXIT

TOTAL_GPUS=$(python3 - <<PY
import json, sys; print(len(json.load(open("$GPU_STATUS"))))
PY)
echo "🖥️ manager up — $TOTAL_GPUS GPU(s) detected"

# ---------- helpers -----------------------------------------------------------
release_gpus() {  # $1 = JOB_ID
python3 - "$1" "$GPU_STATUS" <<'PY'
import json, sys, pathlib
jid, f = sys.argv[1], sys.argv[2]
st = json.load(open(f))
for g in st:
    if st[g] == jid:
        st[g] = None
json.dump(st, open(f, "w"), indent=2)
PY
}

fail_job() {      # $1 = JOB_ID
  user="${1%%_*}"
  [ -d "$QUEUE_ROOT/pending/$user/$1" ] || return
  mkdir -p "$QUEUE_ROOT/failed/$user"
  mv "$QUEUE_ROOT/pending/$user/$1" "$QUEUE_ROOT/failed/$user/" 2>/dev/null || true
}

startup_recovery() {
  for f in "$RUNTIME"/*.ready; do
    [ -e "$f" ] || continue
    jid=$(basename "$f" .ready)
    echo "↻ recover $jid"
    release_gpus "$jid"; fail_job "$jid"; rm -f "$f"
    sed -i "/^${jid}:/d" "$QUEUE_FILE"
  done
}
startup_recovery
# ------------------------------------------------------------------------------

while true; do
  # 1 Watch-dog — limpia runners colgados
  while IFS= read -r -d '' rf; do
    jid=$(basename "$rf" .ready)
    echo "⚠️ stale $jid  (>${STALE_MINUTES} min) — cleaning"
    release_gpus "$jid"; fail_job "$jid"
    rm -f "$rf"; sed -i "/^${jid}:/d" "$QUEUE_FILE"
  done < <(find "$RUNTIME" -name '*.ready' -mmin +"$STALE_MINUTES" -print0)

  # 2 nada en cola
  [ ! -s "$QUEUE_FILE" ] && { sleep "$SLEEP_IDLE"; continue; }

  # 3 leer todas las líneas y elegir la de mayor prioridad que quepa
  mapfile -t LINES < "$QUEUE_FILE"
  PICK_IDX=-1; BEST_PRIO=99; FREE_GPUS=""
  for idx in "${!LINES[@]}"; do
    IFS=':' read -r jid req prio <<<"${LINES[$idx]}"
    prio=${prio:-2}
    [[ $req =~ ^[0-9]+$ ]] || continue
    [[ $prio =~ ^[0-9]+$ ]] || prio=2
    # ¿hay GPUs suficientes?
    free=$(python3 - <<PY
import json, sys, os
req=int("$req")
st=json.load(open("$GPU_STATUS"))
avail=[g for g,v in st.items() if v is None]
print(",".join(avail[:req]) if len(avail)>=req else "", end="")
PY)
    [ -z "$free" ] && continue
    if (( prio < BEST_PRIO )); then
      PICK_IDX=$idx; BEST_PRIO=$prio; FREE_GPUS=$free
    fi
  done

  # 4 si ninguno cabe
  [ $PICK_IDX -lt 0 ] && { sleep 1; continue; }

  IFS=':' read -r JID REQ PRIO <<<"${LINES[$PICK_IDX]}"
  echo "🚀 dispatch $JID (p=$PRIO) → [$FREE_GPUS]"

  # 5 reservar GPUs
  python3 - <<PY
import json, sys
jid="$JID"; gpus="$FREE_GPUS".split(',')
st=json.load(open("$GPU_STATUS"))
for g in gpus: st[g]=jid
json.dump(st, open("$GPU_STATUS","w"), indent=2)
PY

  # 6 ready + desencolar
  echo "$FREE_GPUS" > "$RUNTIME/${JID}.ready"
  sed -i "$((PICK_IDX+1))d" "$QUEUE_FILE"
done
