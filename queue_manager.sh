#!/bin/bash
#
# queue_manager.sh  — despacha trabajos GPU y vigila runners colgados

# ------------ Configuración ------------
QUEUE_ROOT="./dam/queue_jobs"
STALE_MINUTES=2          # .ready sin tocar > 30 min ⇒ marcar failed
SLEEP_IDLE=5              # seg. entre iteraciones si la cola está vacía
# ------------ Fin config ---------------

RUNTIME_DIR="$QUEUE_ROOT/runtime"
PENDING_DIR="$QUEUE_ROOT/pending"
FAILED_DIR="$QUEUE_ROOT/failed"
LOCK_FILE="$RUNTIME_DIR/.manager.lock"
QUEUE_FILE="$RUNTIME_DIR/queue_state.txt"
GPU_STATUS_FILE="$RUNTIME_DIR/gpu_status.json"

mkdir -p "$RUNTIME_DIR" "$FAILED_DIR"

cleanup() {
  echo "Queue manager shutting down…"
  rm -f "$LOCK_FILE"
  exit 0
}
trap cleanup SIGINT SIGTERM EXIT

if [ -f "$LOCK_FILE" ]; then
  echo "Error: queue_manager already running (lock file exists)."
  exit 1
fi
touch "$LOCK_FILE"

# ---------- Funciones util ----------
release_job_gpus () {
  local job_id="$1"
  python3 - <<PY
import json, os, sys
f, jid = "$GPU_STATUS_FILE", "$job_id"
if not os.path.exists(f): sys.exit()
with open(f) as j: status = json.load(j)
changed = False
for gpu, owner in status.items():
    if owner == jid:
        status[gpu] = None
        changed = True
if changed:
    with open(f, "w") as j: json.dump(status, j, indent=2)
PY
}

fail_job () {
  local job_id="$1"
  local username
  username=$(echo "$job_id" | cut -d'_' -f1)
  if [ -d "$PENDING_DIR/$username/$job_id" ]; then
      mkdir -p "$FAILED_DIR/$username"
      mv "$PENDING_DIR/$username/$job_id" "$FAILED_DIR/$username/"
      echo "→ Moved $job_id to failed/"
  fi
}

check_stale_ready () {
  local stale
  while IFS= read -r -d '' stale; do
      local job_id
      job_id=$(basename "$stale" .ready)
      echo "⚠️  Stale job detected: $job_id (>$STALE_MINUTES min). Cleaning…"
      release_job_gpus "$job_id"
      fail_job "$job_id"
      rm -f "$stale"
      sed -i "/^${job_id}:/d" "$QUEUE_FILE"
  done < <(find "$RUNTIME_DIR" -name "*.ready" -mmin +$STALE_MINUTES -print0)
}

startup_recovery () {
  echo "Startup recovery…"
  for rf in "$RUNTIME_DIR"/*.ready; do
      [ -e "$rf" ] || continue
      job_id=$(basename "$rf" .ready)
      echo "Recovering stale job $job_id"
      release_job_gpus "$job_id"
      fail_job "$job_id"
      rm -f "$rf"
      sed -i "/^${job_id}:/d" "$QUEUE_FILE"
  done
  echo "Recovery complete."
}
# --------------------------------------

startup_recovery
echo "✅ Queue manager running. Monitoring $QUEUE_FILE"

while true; do
    # 1) Limpieza watchdog
    check_stale_ready

    # 2) Si la cola está vacía, dormimos
    if [ ! -s "$QUEUE_FILE" ]; then
        sleep "$SLEEP_IDLE"
        continue
    fi

    # 3) Leemos la PRIMERA línea
    IFS=: read -r JOB_ID REQUESTED_GPUS < <(head -n 1 "$QUEUE_FILE")

    # Validación rápida
    [[ -z "$JOB_ID" || ! "$REQUESTED_GPUS" =~ ^[1-2]$ ]] && {
        echo "⚠️  Invalid line '$JOB_ID:$REQUESTED_GPUS' → drop"
        tail -n +2 "$QUEUE_FILE" > "$QUEUE_FILE.tmp" && mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"
        continue
    }

    # 4) ¿Hay GPUs libres suficientes?
    AVAILABLE_GPUS=$(python3 - <<PY
import json, os
f="$GPU_STATUS_FILE"; req=int("$REQUESTED_GPUS")
with open(f) as j: s=json.load(j)
free=[g for g,v in s.items() if v is None]
print(",".join(free[:req]) if len(free)>=req else "", end="")
PY
)
    [ -z "$AVAILABLE_GPUS" ] && { sleep 2; continue; }

    echo "Dispatching $JOB_ID → GPU(s) $AVAILABLE_GPUS"

    # 5) Reservamos GPUs
    python3 - <<PY
import json, os
f="$GPU_STATUS_FILE"; jid="$JOB_ID"; gpus="$AVAILABLE_GPUS".split(',')
with open(f) as j: s=json.load(j)
for g in gpus: s[g]=jid
with open(f,"w") as j: json.dump(s,j,indent=2)
PY

    # 6) Creamos .ready y DESENCOLAMOS ya
    echo "$AVAILABLE_GPUS" > "$RUNTIME_DIR/${JOB_ID}.ready"
    tail -n +2 "$QUEUE_FILE" > "$QUEUE_FILE.tmp" && mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"

    # 7) Iteración inmediata: así podemos despachar más trabajos sin esperar
done

