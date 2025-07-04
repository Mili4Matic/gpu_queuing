#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# wrap_installer.sh
#
# Instala o actualiza dos wrappers globales en /usr/local/bin:
#   • gpurunner  →  llama a user_runner.sh con nohup (sobrevive al logout)
#   • gpuqueue   →  muestra la cola con queue_monitor.sh
#
# Uso:
#   sudo ./wrap_installer.sh /ruta/a/tu/proyecto
#   (si omites la ruta, usa el directorio actual)
#
# Para desinstalar:
#   sudo rm /usr/local/bin/gpurunner /usr/local/bin/gpuqueue
#   sudo rm -f /etc/bash_completion.d/gpurunner
# -----------------------------------------------------------------------------
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
RUNNER="$PROJECT_DIR/user_runner.sh"
MONITOR="$PROJECT_DIR/queue_monitor.sh"

# --- Comprobaciones ----------------------------------------------------------
for f in "$RUNNER" "$MONITOR"; do
  [[ -x "$f" ]] || { echo " Falta o no es ejecutable: $f"; exit 1; }
done

echo "Instalando wrappers que apuntan a:"
echo "  • $RUNNER"
echo "  • $MONITOR"

# --- Instalar gpurunner (nohup + background) ---------------------------------
sudo tee /usr/local/bin/gpurunner >/dev/null <<EOF
#!/usr/bin/env bash
exec nohup "$RUNNER" "\$@" >/dev/null 2>&1 &
EOF
sudo chmod +x /usr/local/bin/gpurunner

# --- Instalar gpuqueue -------------------------------------------------------
sudo tee /usr/local/bin/gpuqueue >/dev/null <<EOF
#!/usr/bin/env bash
exec "$MONITOR" "\$@"
EOF
sudo chmod +x /usr/local/bin/gpuqueue

# --- (Opcional) autocompletado bash para gpurunner ---------------------------
sudo tee /etc/bash_completion.d/gpurunner >/dev/null <<'COMP'
# Autocompletado mínimo para gpurunner: sugiere archivos *.py
_gpurunner() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=( $(compgen -f -X '!*.py' -- "$cur") )
}
complete -F _gpurunner gpurunner
COMP

# --- Mensaje final -----------------------------------------------------------
echo "Wrappers instalados:"
echo "   • gpurunner  (jobs persisten tras logout)"
echo "   • gpuqueue   (monitorea la cola)"
echo " Abre una nueva terminal o ejecuta 'hash -r' para refrescar el PATH."
