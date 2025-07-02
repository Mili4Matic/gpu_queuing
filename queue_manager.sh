#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# queue_manager.sh — despacha y procesa trabajos con 1..N GPUs y vigila runners colgados
# -----------------------------------------------------------------------------
set -euo pipefail

# --- Config ------------------------------------------------------------------
QUEUE_ROOT="./opt/queue_jobs" # Directorio raiz para el sistema de colas
RUNTIME="$QUEUE_ROOT/runtime"
LOCK="$RUNTIME/.manager.lock"
QUEUE="$RUNTIME/queue_state.txt"
GPU_JSON="$RUNTIME/gpu_status.json"
STALE_MINUTES=1 # Minutos sin heartbeat para considerar un trabajo colgado
SLEEP_IDLE=5 
# -----------------------------------------------------------------------------

mkdir -p "$RUNTIME"

[ -e "$LOCK" ] && { echo "Ya hay un manager activo."; exit 1; }
touch "$LOCK"
trap 'rm -f "$LOCK"; exit 0' SIGINT SIGTERM EXIT

TOTAL_GPUS=$(python3 - <<PY
import json, sys, pathlib
print(len(json.load(open("$GPU_JSON"))))
PY
)

echo "🖥️ Manager iniciado. GPUs detectadas: $TOTAL_GPUS"

# ---------- utilidades -------------------------------------------------------
release_gpus() {  # $1=JOB_ID
python3 - <<PY
import json, sys, os
f="$GPU_JSON"; jid="$1"
with open(f) as j: s=json.load(j)
for g in s:
    if s[g]==jid: s[g]=None
with open(f,"w") as j: json.dump(s,j,indent=2)
PY
}

fail_job() {  # $1=JOB_ID
  user=${1%%_*}
  [ -d "$QUEUE_ROOT/pending/$user/$1" ] || return
  mkdir -p "$QUEUE_ROOT/failed/$user"
  mv "$QUEUE_ROOT/pending/$user/$1" "$QUEUE_ROOT/failed/$user/"
}

startup_recovery() {
  echo "→ Recovery..."
  for f in "$RUNTIME"/*.ready; do
    [ -e "$f" ] || continue
    jid=$(basename "$f" .ready)
    release_gpus "$jid"
    fail_job "$jid"
    rm -f "$f"
    sed -i "/^${jid}:/d" "$QUEUE"
    echo "  Recup $jid"
  done
}
startup_recovery
# -----------------------------------------------------------------------------


while true; do
  # 1 Limpiar .ready sin heartbeat
  while IFS= read -r -d '' f; do
      jid=$(basename "$f" .ready)
      echo "  Stale $jid (>${STALE_MINUTES}m). Proccess DEAD, QUEUE Cleanup."
      release_gpus "$jid"; fail_job "$jid"; rm -f "$f"
      sed -i "/^${jid}:/d" "$QUEUE"
  done < <(find "$RUNTIME" -name '*.ready' -mmin +"$STALE_MINUTES" -print0)

  # 2 Cola vacía
  [ ! -s "$QUEUE" ] && { sleep "$SLEEP_IDLE"; continue; }

  # 3 Leer primera línea
  IFS=: read -r JID REQ < <(head -n 1 "$QUEUE")
  if ! [[ "$REQ" =~ ^[0-9]+$ ]] || [ "$REQ" -lt 1 ] || [ "$REQ" -gt "$TOTAL_GPUS" ]; then
      echo "  Entrada inválida: $JID:$REQ"
      tail -n +2 "$QUEUE" > "$QUEUE.tmp" && mv "$QUEUE.tmp" "$QUEUE"
      continue
  fi

  # 4 GPUs libres
  FREE=$(python3 - <<PY
import json, sys
req=int("$REQ")
with open("$GPU_JSON") as j: s=json.load(j)
free=[g for g,v in s.items() if v is None]
print(",".join(free[:req]) if len(free)>=req else "", end="")
PY
)
  [ -z "$FREE" ] && { sleep 1; continue; }

  echo " Dispatch $JID → [$FREE]"
  # 5 Reservar
python3 - <<PY
import json, os
jid="$JID"; gpus="$FREE".split(',')
with open("$GPU_JSON") as j: s=json.load(j)
for g in gpus: s[g]=jid
with open("$GPU_JSON","w") as j: json.dump(s,j,indent=2)
PY

  echo "$FREE" > "$RUNTIME/${JID}.ready"
  tail -n +2 "$QUEUE" > "$QUEUE.tmp" && mv "$QUEUE.tmp" "$QUEUE"
done
