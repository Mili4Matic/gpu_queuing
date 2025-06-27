#!/bin/bash

# --- Configuration ---
QUEUE_ROOT="/home/linuxbida/Escritorio/VBoxTools/queue_jobs"
# --- End Configuration ---

RUNTIME_DIR="$QUEUE_ROOT/runtime"
QUEUE_FILE="$RUNTIME_DIR/queue_state.txt"
GPU_STATUS_FILE="$RUNTIME_DIR/gpu_status.json"

# Colors
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_RED='\033[0;31m'
C_BLUE='\033[0;34m'
C_NC='\033[0m' # No Color

# Use watch for continuous monitoring
watch -n 2 -t -c "
echo \"--- GPU Queue Monitor --- $(date) --- (Updates every 2s, press Ctrl+C to exit)\"
echo \"\"

# --- GPU Status ---
echo -e \"${C_BLUE}GPU Status:${C_NC}\"
if [ -f \"$GPU_STATUS_FILE\" ]; then
    python3 -c \"
import json
import os
f = '$GPU_STATUS_FILE'
colors = {'green': '\\033[0;32m', 'yellow': '\\033[0;33m', 'nc': '\\033[0m'}
if not os.path.exists(f): exit()
with open(f, 'r') as j:
    status = json.load(j)
output = []
for gpu, job in sorted(status.items()):
    if job is None:
        output.append(f\\\"{colors['green']}GPU {gpu}: FREE{colors['nc']}\\\")
    else:
        output.append(f\\\"{colors['yellow']}GPU {gpu}: USED by {job}{colors['nc']}\\\")
print(' | '.join(output))
\"
else
    echo -e \"${C_RED}GPU status file not found!${C_NC}\"
fi
echo \"\"

# --- Job Queue ---
echo -e \"${C_BLUE}Pending Jobs:${C_NC}\"
if [ -s \"$QUEUE_FILE\" ]; then
    echo -e \"Position  |  Job ID                               |  GPUs Req.\"
    echo \"--------------------------------------------------------------------\"
    nl -w10 -s'  |  ' \"$QUEUE_FILE\" | sed 's/:/  |  /'
else
    echo \"Queue is empty.\"
fi
"