#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# queue_monitor.sh — muestra la cola GPU y resalta tus jobs (sin ETA ni PRIO)
# -----------------------------------------------------------------------------
set -euo pipefail

QUEUE_ROOT="./dam/queue_jobs"
RUNTIME="$QUEUE_ROOT/runtime"
QUEUE_FILE="$RUNTIME/queue_state.txt"
GPU_STATUS_FILE="$RUNTIME/gpu_status.json"
USERNAME=$(whoami)

BOLD="\e[1m"; GREEN="\e[32m"; CYAN="\e[36m"; RESET="\e[0m"

while true; do
    clear

    [[ -f "$QUEUE_FILE" ]] || { echo "No existe $QUEUE_FILE"; exit 1; }

    # Info GPUs
    TOTAL_GPUS=$(python3 - <<PY
import json, sys
print(len(json.load(open("$GPU_STATUS_FILE"))))
PY)
    FREE_GPUS=$(python3 - <<PY
import json
print(sum(1 for v in json.load(open("$GPU_STATUS_FILE")).values() if v is None))
PY)

    echo -e "\nGPU total: $TOTAL_GPUS  libres: $FREE_GPUS\n"

    printf "%-3s %-38s %-5s %-6s\n" "#" "JOB_ID" "GPUs" "USER"
    printf "%-3s %-38s %-5s %-6s\n" "--" "--------------------------------------" "-----" "------"

    line=0
    while IFS=: read -r jid req _; do
        [[ -z "$jid" || -z "$req" ]] && continue
        user=${jid%%_*}
        line=$((line+1))
        if [ "$user" = "$USERNAME" ]; then
            printf "${BOLD}${GREEN}%-3s %-38s %-5s %-6s${RESET}\n" \
                         "$line" "${jid:0:38}" "$req" "$user"
        else
            printf "%-3s %-38s %-5s %-6s\n" \
                         "$line" "${jid:0:38}" "$req" "$user"
        fi
    done < "$QUEUE_FILE"

    # Jobs en ejecución
    printf "\n${CYAN}RUNNING:${RESET}\n"
    found=0
    for rf in "$RUNTIME"/*.ready; do
        [ -e "$rf" ] || continue
        found=1
        jid=$(basename "$rf" .ready)
        gpus=$(<"$rf")
        user=${jid%%_*}
        if [ "$user" = "$USERNAME" ]; then c="${GREEN}${BOLD}"; else c=""; fi
        printf "${c}%s -> [%s]${RESET}\n" "$jid" "$gpus"
    done
    [ $found -eq 0 ] && echo "(sin jobs en ejecución)"

    sleep 2
done
