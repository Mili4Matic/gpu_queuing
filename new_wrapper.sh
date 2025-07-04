#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# wrap_installer.sh
#
# Instala / actualiza dos wrappers globales en /usr/local/bin
#   • gpurunner  →  llama user_runner.sh (nohup bg) y muestra JOB_ID
#   • gpuqueue   →  muestra la cola con queue_monitor.sh
#
# Uso:
#   sudo ./wrap_installer.sh /ruta/a/tu/proyecto
#   (si omites la ruta, usa $(pwd))
#
# Desinstalar:
#   sudo rm /usr/local/bin/gpurunner /usr/local/bin/gpuqueue
#   sudo rm -f /etc/bash_completion.d/gpurunner
# -----------------------------------------------------------------------------
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
RUNNER="$PROJECT_DIR/user_runner.sh"
MONITOR="$PROJECT_DIR/queue_monitor.sh"

for f in "$RUNNER" "$MONITOR"; do
  [[ -x "$f" ]] || { echo "Falta o no es ejecutable: $f"; exit 1; }
done

echo "Instalando wrappers que apuntan a:"
echo "  • $RUNNER"
echo "  • $MONITOR"

# -------- gpurunner con JOB_ID visible ---------------------------------------
sudo tee /usr/local/bin/gpurunner >/dev/null <<EOF
#!/usr/bin/env bash
# Wrapper global: lanza user_runner con nohup y muestra JOB_ID

RUNNER="$RUNNER"

LOG=\$(mktemp -t gpurunner.XXXX)
nohup "\$RUNNER" "\$@" >"\$LOG" 2>&1 &
sleep 0.5
if JOB=\$(grep -m1 '^JOB_ID=' "\$LOG"); then
  echo "\$JOB"
else
  echo " JOB_ID no capturado — revisa el log en dam/queue_jobs/logs/"
fi
rm -f "\$LOG"
EOF
sudo chmod +x /usr/local/bin/gpurunner

# -------- gpuqueue -----------------------------------------------------------
sudo tee /usr/local/bin/gpuqueue >/dev/null <<EOF
#!/usr/bin/env bash
exec "$MONITOR" "\$@"
EOF
sudo chmod +x /usr/local/bin/gpuqueue

# -------- Autocompletado opcional -------------------------------------------
sudo tee /etc/bash_completion.d/gpurunner >/dev/null <<'COMP'
_gpurunner() {
  local cur="\${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=( \$(compgen -f -X '!*.py' -- "$cur") )
}
complete -F _gpurunner gpurunner
COMP

echo "Wrappers instalados:"
echo "   • gpurunner  (nohup bg + JOB_ID)"
echo "   • gpuqueue   (monitor de cola)"
echo "Abre nueva terminal o ejecuta 'hash -r' para refrescar PATH."
