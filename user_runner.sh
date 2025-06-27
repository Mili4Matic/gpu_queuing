#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# user_runner.sh  — envía un trabajo a la cola y lo ejecuta cuando haya GPU(s)
# -----------------------------------------------------------------------------
set -euo pipefail

QUEUE_ROOT="./dam/queue_jobs"
HEARTBEAT_SECS=30

# --- Parseo de argumentos ----------------------------------------------------
if [[ "${1-}" == "--gpus" && -n "${2-}" ]]; then
    NUM_GPUS="$2"; shift 2
else
    echo "Uso: $0 --gpus <1-N> /ruta/a/script.py"; exit 1
fi
SCRIPT_PATH=$(realpath "$1") || exit 1
[[ -f "$SCRIPT_PATH" ]] || { echo "Error: no existe $SCRIPT_PATH"; exit 1; }

TOTAL_GPUS=$(nvidia-smi --list-gpus | wc -l)
if ! [[ "$NUM_GPUS" =~ ^[0-9]+$ ]] || [ "$NUM_GPUS" -lt 1 ] || [ "$NUM_GPUS" -gt "$TOTAL_GPUS" ]; then
    echo "Error: --gpus debe estar entre 1 y $TOTAL_GPUS"; exit 1
fi

# --- Rutas y Job-ID ----------------------------------------------------------
USERNAME=$(whoami)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RAND=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c5)
JOB_ID="${USERNAME}_${TIMESTAMP}_${RAND}"

PENDING="$QUEUE_ROOT/pending/$USERNAME/$JOB_ID"
RUNTIME="$QUEUE_ROOT/runtime"
LOGDIR="$QUEUE_ROOT/logs"
mkdir -p "$PENDING" "$LOGDIR"

ln -s "$SCRIPT_PATH" "$PENDING/$(basename "$SCRIPT_PATH")"

echo -e "\e[1mJob submitted with ID: $JOB_ID\e[0m"
echo "Job requires $NUM_GPUS GPU(s)."

echo "${JOB_ID}:${NUM_GPUS}" >> "$RUNTIME/queue_state.txt"

# --- Spinner mientras esperamos turno ---------------------------------------
spin=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏); i=0
until [ -f "$RUNTIME/${JOB_ID}.ready" ]; do
    pos=$(grep -n "^${JOB_ID}:" "$RUNTIME/queue_state.txt" | cut -d: -f1)
    printf "\r[%s] Waiting… position %s " "${spin[i]}" "${pos:-?}"; i=$(( (i+1)%10 ))
    sleep 0.2
done

echo -e "\n\e[32mIt's your turn! Preparing...\e[0m"

GPU_IDS=$(cat "$RUNTIME/${JOB_ID}.ready")
export CUDA_VISIBLE_DEVICES="$GPU_IDS"
READY_FILE="$RUNTIME/${JOB_ID}.ready"
echo "Assigned GPU(s) ID(s): $CUDA_VISIBLE_DEVICES"

# --- Heartbeat --------------------------------------------------------------
( while true; do sleep "$HEARTBEAT_SECS"; [ -f "$READY_FILE" ] && touch "$READY_FILE" || exit 0; done ) & HB=$!

# --- Limpieza segura (SIGINT/SIGTERM) ---------------------------------------
cleanup() {
    code=$1
    kill "$HB" 2>/dev/null || true
    rm -f "$READY_FILE"
python3 - <<PY
import json, os, sys
f="$RUNTIME/gpu_status.json"; jid="$JOB_ID"
if os.path.exists(f):
  with open(f) as j: s=json.load(j)
  for g in s:
    if s[g]==jid: s[g]=None
  with open(f,"w") as j: json.dump(s,j,indent=2)
PY
    mkdir -p "$QUEUE_ROOT/failed/$USERNAME"
    mv "$PENDING" "$QUEUE_ROOT/failed/$USERNAME/" 2>/dev/null || true
    echo -e "\n\e[31m❌ Job interrupted.\e[0m"
    exit "$code"
}
trap 'cleanup 130' SIGINT SIGTERM

# --- Detectar conda env ------------------------------------------------------
ENV=$(grep -m1 -i "^# *conda_env" "$SCRIPT_PATH" | sed -E 's/^# *conda_env:?[ ]*//')
[[ -z "$ENV" ]] && { echo "Falta # conda_env en el script"; cleanup 1; }

source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate "$ENV" || { echo "No existe env $ENV"; cleanup 1; }

# --- Ejecución --------------------------------------------------------------
stdbuf -oL python -u "$SCRIPT_PATH" 2>&1 | tee "$LOGDIR/${JOB_ID}.log" & CHILD=$!
wait $CHILD; EXIT=$?

conda deactivate
kill "$HB" 2>/dev/null || true
rm -f "$READY_FILE"

python3 - <<PY
import json, os
f="$RUNTIME/gpu_status.json"; jid="$JOB_ID"
with open(f) as j: s=json.load(j)
for g in s:
    if s[g]==jid: s[g]=None
with open(f,"w") as j: json.dump(s,j,indent=2)
PY

DEST="$QUEUE_ROOT/$( [ $EXIT -eq 0 ] && echo done || echo failed)/$USERNAME"
mkdir -p "$DEST"; mv "$PENDING" "$DEST/"
echo -e "\e[32mJob finished with exit code $EXIT\e[0m"
if [ $EXIT -eq 0 ]; then
    echo "Job completed successfully. Logs at: $LOGDIR/${JOB_ID}.log"
else
    echo "Job failed. Check logs at: $LOGDIR/${JOB_ID}.log"
fi
exit $EXIT
