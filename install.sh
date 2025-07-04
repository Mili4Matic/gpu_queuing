#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# install.sh — Inicializa el sistema de colas GPU
# -----------------------------------------------------------------------------
set -euo pipefail

# --- 1 Crear carpetas base --------------------------------------------------
QUEUE_ROOT="./opt/queue_jobs"
RUNTIME_DIR="$QUEUE_ROOT/runtime"
mkdir -p "$QUEUE_ROOT"/{pending,done,failed,logs} "$RUNTIME_DIR"

# Si no detecta nvidia-smi, poner la ruta completa, se encuentra con command -v nvidia-smi
# --- 2  Detectar GPUs con nvidia-smi ----------------------------------------
TOTAL_GPUS=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
if [ "$TOTAL_GPUS" -lt 1 ]; then
  echo "No se han detectado GPUs con nvidia-smi. Abortando."
  exit 1
fi
echo "→ Detectadas $TOTAL_GPUS GPU(s)."

# --- 3  Generar gpu_status.json en base al nimero de GPUs detectadas ---------
python3 - <<PY
import json, pathlib
n = $TOTAL_GPUS
path = pathlib.Path("$RUNTIME_DIR") / "gpu_status.json"
json.dump({str(i): None for i in range(n)}, path.open("w"), indent=2)
PY

touch "$RUNTIME_DIR/queue_state.txt"

# --- 4  Dar permisos ejecutables a todos los .sh del directorio -------------
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
find "$SCRIPT_DIR" -maxdepth 1 -type f -name "*.sh" -exec chmod +x {} \;

# --- 5  Mensaje final --------------------------------------------------------
echo " Instalación completada en $(realpath "$QUEUE_ROOT")"
echo "  Todas los scripts *.sh están ahora marcados como ejecutables."
echo "   Lanza ./queue_manager.sh & o habilita el servicio systemd."
