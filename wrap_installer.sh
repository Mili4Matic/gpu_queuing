#!/usr/bin/env bash
# install_wrappers.sh
# ---------------------------------------------------------------------------
# Crea accesos directos globales a user_runner.sh y queue_monitor.sh
# Copia o enlaza en /usr/local/bin  → disponibles para todos los usuarios
# Uso:
#   sudo ./install_wrappers.sh /ruta/a/tu/proyecto
#   (si omites la ruta, asume el directorio actual)
# ---------------------------------------------------------------------------

set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"          # ubicación de los scripts reales
RUNNER="$PROJECT_DIR/user_runner.sh"
MONITOR="$PROJECT_DIR/queue_monitor.sh"

# Comprobaciones básicas
for f in "$RUNNER" "$MONITOR"; do
  [[ -x "$f" ]] || { echo "❌ No se encontró o no es ejecutable: $f"; exit 1; }
done

# Instalar / actualizar wrappers
install -m 0755 -T <(cat <<'WRAP'
#!/usr/bin/env bash
exec /opt/gpu_queue/user_runner.sh "$@"
WRAP
) /usr/local/bin/gpurunner

install -m 0755 -T <(cat <<'WRAP'
#!/usr/bin/env bash
exec /opt/gpu_queue/queue_monitor.sh "$@"
WRAP
) /usr/local/bin/gpuqueue

echo "✅ Creado gpurunner y gpuqueue en /usr/local/bin"

# Opcional: autocompletado básico para bash
cat >/etc/bash_completion.d/gpurunner <<'COMP'
_gpurunner_complete() { COMPREPLY=(); }
complete -F _gpurunner_complete gpurunner
COMP

echo "ℹ️  Abre una nueva terminal o haz 'hash -r' para refrescar el PATH."

