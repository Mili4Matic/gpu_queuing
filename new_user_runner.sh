#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# user_runner.sh — Encola y ejecuta un script Python en la cola GPU
#   · Heartbeat ligado al PID del proceso Python (evita zombies)
#   · Mueve OK/KO a done/<user> o failed/<user>
#   · Imprime JOB_ID en la primera línea para que un wrapper pueda capturarlo
# -----------------------------------------------------------------------------
set -euo pipefail

# ---------- Argumentos -------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    --gpus) NUM_GPUS="$2"; shift 2 ;;
    *)      SCRIPT_PATH="$1"; shift ;;
  esac
done

[[ -z "${NUM_GPUS:-}" || -z "${SCRIPT_PATH:-}" ]] && {
  echo "Uso: $0 --gpus <1-N> /ruta/script.py"; exit 1; }

SCRIPT_PATH=$(realpath "$SCRIPT_PATH")
TOTAL_GPUS=$(nvidia-smi --list-gpus | wc -l)
[[ $NUM_GPUS =~ ^[0-9]+$ ]] && (( NUM_GPUS>=1 && NUM_GPUS<=TOTAL_GPUS )) \
  || { echo "--gpus debe estar entre 1 y $TOTAL_GPUS"; exit 1; }

# ---------- Identificación del job ------------------------------------------
QUEUE_ROOT="./dam/queue_jobs"
RUNTIME="$QUEUE_ROOT/runtime"
USERNAME=$(whoami)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RAND=$(date +%s%N | sha256sum | cut -c1-8)

JOB_ID="${USERNAME}_${TIMESTAMP}_${RAND}"
OWNER="${JOB_ID%%_*}"

# → IMPRIMIR ID EN LA PRIMERA LÍNEA (wrapper puede capturarla)
echo "JOB_ID=$JOB_ID"

PENDING="$QUEUE_ROOT/pending/$OWNER/$JOB_ID"
LOGDIR="$QUEUE_ROOT/logs"
mkdir -p "$PENDING" "$LOGDIR" "$RUNTIME"
ln -s "$SCRIPT_PATH" "$PENDING/$(basename "$SCRIPT_PATH")"

echo "queued  ($NUM_GPUS GPU)"

echo "${JOB_ID}:${NUM_GPUS}" >> "$RUNTIME/queue_state.txt"

# ---------- Esperar turno ----------------------------------------------------
spin=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏); i=0
until [ -f "$RUNTIME/${JOB_ID}.ready" ]; do
  pos=$(grep -n "^${JOB_ID}:" "$RUNTIME/queue_state.txt" | cut -d: -f1)
  printf "\r[%s] waiting… position %s " "${spin[i]}" "${pos:-?}"
  i=$(( (i+1)%10 )); sleep 0.2
done; echo

GPU_IDS=$(<"$RUNTIME/${JOB_ID}.ready")
export CUDA_VISIBLE_DEVICES="$GPU_IDS"
READY_FILE="$RUNTIME/${JOB_ID}.ready"
echo "🎬 starting on GPU(s): $CUDA_VISIBLE_DEVICES"

# ---------- Ejecutar el script ------------------------------------------------
stdbuf -oL python -u "$SCRIPT_PATH" 2>&1 | tee "$LOGDIR/${JOB_ID}.log" &
CHILD_PID=$!

# ---------- Heartbeat ligado al PID -----------------------------------------
( while kill -0 "$CHILD_PID" 2>/dev/null; do
      sleep 30
      [ -f "$READY_FILE" ] && touch "$READY_FILE"
  done ) & HB=$!

# ---------- Limpieza al interrumpir -----------------------------------------
cleanup() {
  kill "$HB" 2>/dev/null || true
  rm -f "$READY_FILE"
  python3 - <<PY
import json, sys
f="$RUNTIME/gpu_status.json"; jid="$JOB_ID"
st=json.load(open(f)); changed=False
for g in st:
    if st[g]==jid: st[g]=None; changed=True
changed and json.dump(st, open(f,"w"), indent=2)
PY
  mkdir -p "$QUEUE_ROOT/failed/$OWNER"
  mv "$PENDING" "$QUEUE_ROOT/failed/$OWNER/" 2>/dev/null || true
  echo -e "\\n🔻 job interrupted"
  exit 130
}
trap cleanup SIGINT SIGTERM

# ---------- Esperar fin ------------------------------------------------------
wait "$CHILD_PID"; EXIT=$?
kill "$HB" 2>/dev/null || true
rm -f "$READY_FILE"

# ---------- Liberar GPUs -----------------------------------------------------
python3 - <<PY
import json, sys
f="$RUNTIME/gpu_status.json"; jid="$JOB_ID"
st=json.load(open(f))
for g in st:
    if st[g]==jid: st[g]=None
json.dump(st, open(f,"w"), indent=2)
PY

# ---------- Mover a done / failed -------------------------------------------
DEST=$([ $EXIT -eq 0 ] && echo done || echo failed)
mkdir -p "$QUEUE_ROOT/$DEST/$OWNER"
mv "$PENDING" "$QUEUE_ROOT/$DEST/$OWNER/"

echo -e "finished (exit $EXIT)"
exit $EXIT
