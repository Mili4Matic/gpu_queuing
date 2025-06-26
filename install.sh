#!/usr/bin/env bash
# install.sh — prepara la estructura dam/queue_jobs y el gpu_status.json dinámico

set -e

QUEUE_ROOT="./dam/queue_jobs"
RUNTIME_DIR="$QUEUE_ROOT/runtime"
mkdir -p "$QUEUE_ROOT"/{pending,done,failed,logs} "$RUNTIME_DIR"

# ── NUEVO: detecta cuántas GPUs tiene la máquina ───────────────────────────────
TOTAL_GPUS=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
if [ "$TOTAL_GPUS" -lt 1 ]; then
  echo "❌ No se han detectado GPUs con nvidia-smi. Abortando."
  exit 1
fi
echo "→ Detectadas $TOTAL_GPUS GPU(s)."

# Genera gpu_status.json con todas en 'null'
python3 - <<PY
import json, os, sys
n=int(os.environ["TOTAL_GPUS"])
json.dump({str(i): None for i in range(n)}, open("$RUNTIME_DIR/gpu_status.json","w"), indent=2)
PY

# Crea queue_state vacío si no existe
touch "$RUNTIME_DIR/queue_state.txt"

echo "✅ Instalación completada en $(realpath "$QUEUE_ROOT")"
echo "  Lanza ahora ./queue_manager.sh &"
