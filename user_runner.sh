#!/bin/bash
#
# user_runner.sh — envía un trabajo a la cola GPU y lo ejecuta

# --- Configuración ----------------------------------------------------------
QUEUE_ROOT="./dam/queue_jobs"
HEARTBEAT_SECS=30         # cada cuánto se “toca” el .ready
# ---------------------------------------------------------------------------

# ---------- Argument parsing ----------
if [[ "$1" == "--gpus" ]]; then
    NUM_GPUS="$2"; shift 2
else
    echo "Uso: $0 --gpus [1|2] /ruta/tu_script.py"; exit 1
fi
[[ "$NUM_GPUS" =~ ^[12]$ ]] || { echo "Error: --gpus debe ser 1 ó 2"; exit 1; }
SCRIPT_PATH=$(realpath "$1") || exit 1
[[ -f "$SCRIPT_PATH" ]] || { echo "Error: no existe $SCRIPT_PATH"; exit 1; }

# ---------- Rutas y Job-ID ----------
SCRIPT_NAME=$(basename "$SCRIPT_PATH")
USERNAME=$(whoami)
QUEUE_DIR="$QUEUE_ROOT"
PENDING_DIR="$QUEUE_DIR/pending/$USERNAME"
RUNTIME_DIR="$QUEUE_DIR/runtime"
LOGS_DIR="$QUEUE_DIR/logs"
mkdir -p "$PENDING_DIR" "$RUNTIME_DIR" "$LOGS_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RAND_STR=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 5)
JOB_ID="${USERNAME}_${TIMESTAMP}_${RAND_STR}"
JOB_DIR="$PENDING_DIR/$JOB_ID"; mkdir -p "$JOB_DIR"
ln -s "$SCRIPT_PATH" "$JOB_DIR/$SCRIPT_NAME"

echo -e "\e[1mJob submitted with ID: $JOB_ID\e[0m"
echo "Job requires $NUM_GPUS GPU(s)."

# ---------- Alta en la cola ----------
echo "${JOB_ID}:${NUM_GPUS}" >> "$RUNTIME_DIR/queue_state.txt"

# ---------- Espera de turno ----------
spin=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏); i=0
while true; do
    if [ -f "$RUNTIME_DIR/${JOB_ID}.ready" ]; then
        echo -e "\n\e[32m✅ It's your turn! Preparing to execute...\e[0m"; break
    fi
    pos=$(grep -n "^${JOB_ID}:" "$RUNTIME_DIR/queue_state.txt" | cut -d: -f1)
    [[ -z "$pos" ]] && { echo -e "\nLa cola ya no contiene tu job. Abortando."; rm -rf "$JOB_DIR"; exit 1; }
    printf "\r[%s] Waiting… position %s " "${spin[i]}" "$pos"; i=$(( (i+1)%10 ))
    sleep 0.2
done

# ---------- Recursos asignados ----------
GPU_IDS=$(cat "$RUNTIME_DIR/${JOB_ID}.ready")
export CUDA_VISIBLE_DEVICES="$GPU_IDS"
echo "Assigned GPU(s): $CUDA_VISIBLE_DEVICES"
READY_FILE="$RUNTIME_DIR/${JOB_ID}.ready"

# ---------- Latido ----------------------
heartbeat() { while true; do sleep "$HEARTBEAT_SECS"; [ -f "$READY_FILE" ] && touch "$READY_FILE" || exit 0; done; }
heartbeat & HB_PID=$!

# ---------- Limpieza segura -------------
cleanup_and_exit() {
    code=$1
    echo -e "\n🔻 Cleanup (exit $code)…"
    kill "$HB_PID" 2>/dev/null; wait "$HB_PID" 2>/dev/null

    # Si queda un proceso hijo vivo, termínalo
    [ -n "$CHILD_PID" ] && kill -INT "$CHILD_PID" 2>/dev/null

    # Liberar GPUs
python3 - <<PY
import json, os; f="$RUNTIME_DIR/gpu_status.json"; jid="$JOB_ID"
if os.path.exists(f):
  with open(f) as j: s=json.load(j)
  for g in list(s):
    if s[g]==jid: s[g]=None
  with open(f,"w") as j: json.dump(s,j,indent=2)
PY
    rm -f "$READY_FILE"

    dest="$QUEUE_DIR/failed/$USERNAME"; mkdir -p "$dest"
    [ -d "$JOB_DIR" ] && mv "$JOB_DIR" "$dest/"
    echo -e "\e[31m❌ Job interrupted.\e[0m"
    exit "$code"
}
trap 'cleanup_and_exit 130' SIGINT SIGTERM

# ---------- Activar entorno conda -------
ENV_NAME=$(grep -m1 -i "^# *conda_env" "$SCRIPT_PATH" | sed -E 's/^# *conda_env:?[ ]*//;s/[[:space:]]*$//')
[[ -z "$ENV_NAME" ]] && { echo "Sin # conda_env en script."; cleanup_and_exit 1; }
echo "Activating conda env: $ENV_NAME"

CONDA_SH=$(conda info --base 2>/dev/null)/etc/profile.d/conda.sh
source "$CONDA_SH"        || { echo "No puedo source conda.sh"; cleanup_and_exit 1; }
conda activate "$ENV_NAME" || { echo "No existe env $ENV_NAME"; cleanup_and_exit 1; }

# ---------- Ejecución -------------------
cd "$(dirname "$SCRIPT_PATH")"
stdbuf -oL python -u "$SCRIPT_NAME" 2>&1 | tee "$LOGS_DIR/${JOB_ID}.log" &
CHILD_PID=$!
wait "$CHILD_PID"; EXIT_CODE=$?

conda deactivate

# ---------- Fin OK/KO -------------------
kill "$HB_PID" 2>/dev/null; wait "$HB_PID" 2>/dev/null
rm -f "$READY_FILE"

# Libera GPUs
python3 - <<PY
import json, os; f="$RUNTIME_DIR/gpu_status.json"; jid="$JOB_ID"
if os.path.exists(f):
  with open(f) as j: s=json.load(j)
  for g in list(s):
    if s[g]==jid: s[g]=None
  with open(f,"w") as j: json.dump(s,j,indent=2)
PY
echo "Released GPUs."

if [ $EXIT_CODE -eq 0 ]; then
    mkdir -p "$QUEUE_DIR/done/$USERNAME"
    mv "$JOB_DIR" "$QUEUE_DIR/done/$USERNAME/"
    echo -e "\e[32m✅ Job finished OK.\e[0m"
else
    mkdir -p "$QUEUE_DIR/failed/$USERNAME"
    mv "$JOB_DIR" "$QUEUE_DIR/failed/$USERNAME/"
    echo -e "\e[31m❌ Job failed (exit $EXIT_CODE).\e[0m"
fi

exit $EXIT_CODE

