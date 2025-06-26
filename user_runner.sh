#!/usr/bin/env bash
# user_runner.sh — enqueue & run, supports --priority and checkpoint resume
set -euo pipefail

# -------- parse args ----------------------------------------------------------
PRIORITY="normal"          # high | normal | low
while [[ $# -gt 0 ]]; do
  case $1 in
    --gpus)     NUM_GPUS="$2"; shift 2 ;;
    --priority) PRIORITY="$2"; shift 2 ;;
    *)          SCRIPT_PATH="$1"; shift ;;
  esac
done

[[ -z "${NUM_GPUS:-}" || -z "${SCRIPT_PATH:-}" ]] && {
  echo "Uso: $0 --gpus <1-N> [--priority high|normal|low] script.py"; exit 1; }

SCRIPT_PATH=$(realpath "$SCRIPT_PATH")
TOTAL_GPUS=$(nvidia-smi --list-gpus | wc -l)
[[ $NUM_GPUS =~ ^[0-9]+$ ]] && (( NUM_GPUS>=1 && NUM_GPUS<=TOTAL_GPUS )) \
  || { echo "❌ --gpus debe estar entre 1 y $TOTAL_GPUS"; exit 1; }

case $PRIORITY in high) PRIO_NUM=1;; normal) PRIO_NUM=2;; low) PRIO_NUM=3;;
  *) echo "❌ prioridad debe ser high|normal|low"; exit 1;; esac

# -------- directories & job id -----------------------------------------------
QUEUE_ROOT="./dam/queue_jobs"
RUNTIME="$QUEUE_ROOT/runtime"
USERNAME=$(whoami)
JOB_ID="${USERNAME}_$(date +%Y%m%d_%H%M%S)_$(tr -dc A-Za-z0-9 </dev/urandom | head -c5)"

PENDING="$QUEUE_ROOT/pending/$USERNAME/$JOB_ID"
LOGDIR="$QUEUE_ROOT/logs"
mkdir -p "$PENDING" "$LOGDIR" "$RUNTIME"
ln -s "$SCRIPT_PATH" "$PENDING/$(basename "$SCRIPT_PATH")"

echo -e "📤 queued $JOB_ID (priority=$PRIORITY, $NUM_GPUS GPU)"

echo "${JOB_ID}:${NUM_GPUS}:${PRIO_NUM}" >> "$RUNTIME/queue_state.txt"

# -------- wait for .ready -----------------------------------------------------
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

# -------- heartbeat -----------------------------------------------------------
HEARTBEAT_SECS=30
( while true; do sleep $HEARTBEAT_SECS; [ -f "$READY_FILE" ] && touch "$READY_FILE" || exit 0; done ) & HB=$!

# -------- cleanup on interrupt ------------------------------------------------
cleanup(){ code=$1
  kill "$HB" 2>/dev/null || true
  rm -f "$READY_FILE"
  python3 - <<PY
import json; f="$RUNTIME/gpu_status.json"; jid="$JOB_ID"
st=json.load(open(f)); changed=False
for g in st: 
    if st[g]==jid: st[g]=None; changed=True
changed and json.dump(st,open(f,"w"),indent=2)
PY
  mkdir -p "$QUEUE_ROOT/failed/$USERNAME"
  mv "$PENDING" "$QUEUE_ROOT/failed/$USERNAME/" 2>/dev/null || true
  echo -e "\n🔻 job interrupted"; exit "$code"
}
trap 'cleanup 130' SIGINT SIGTERM

# -------- conda env detection -------------------------------------------------
ENV=$(grep -m1 -i "^# *conda_env" "$SCRIPT_PATH" | sed -E 's/^# *conda_env:? *//') || true
source "$(conda info --base)/etc/profile.d/conda.sh"
[ -n "$ENV" ] && conda activate "$ENV" || echo "(no conda env specified)"

# -------- run -----------------------------------------------------------------
stdbuf -oL python -u "$SCRIPT_PATH" 2>&1 | tee "$LOGDIR/${JOB_ID}.log" &
PID=$!; wait $PID; EXIT=$?

[ -n "$ENV" ] && conda deactivate
kill "$HB" 2>/dev/null || true
rm -f "$READY_FILE"

# -------- release GPUs --------------------------------------------------------
python3 - <<PY
import json; f="$RUNTIME/gpu_status.json"; jid="$JOB_ID"; st=json.load(open(f))
for g in st: 
    if st[g]==jid: st[g]=None
json.dump(st, open(f,"w"), indent=2)
PY

# -------- checkpoint / normal finish ------------------------------------------
if [ $EXIT -eq 75 ]; then           # 75 = checkpoint code
  echo "💾 checkpoint exit — re-enqueuing"
  NEW_ID="${JOB_ID}_res"
  mv "$PENDING" "$QUEUE_ROOT/pending/$USERNAME/$NEW_ID"
  echo "${NEW_ID}:${NUM_GPUS}:${PRIO_NUM}" >> "$RUNTIME/queue_state.txt"
  exit 0
fi

DEST=$([ $EXIT -eq 0 ] && echo done || echo failed)
mkdir -p "$QUEUE_ROOT/$DEST/$USERNAME"
mv "$PENDING" "$QUEUE_ROOT/$DEST/$USERNAME/"
echo -e "✅ finished (exit $EXIT)"
exit $EXIT
