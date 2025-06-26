#!/bin/bash

# This script sets up the directory structure and initial state for the GPU queue system.

# --- Configuration ---
# The root directory for the entire queue system.
# IMPORTANT: This path must match the one in queue_manager.sh and user_runner.sh
QUEUE_ROOT="./dam/queue_jobs"
NUM_GPUS=2 # Total number of GPUs on this server (e.g., 4 for H100s)

# --- Script Logic ---
echo "--- GPU Queue System Installer ---"

# Check if root directory already exists
if [ -d "$QUEUE_ROOT" ]; then
    read -p "Installation directory '$QUEUE_ROOT' already exists. Overwrite initial files? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 1
    fi
else
    echo "Creating queue system directory at: $QUEUE_ROOT"
    mkdir -p "$QUEUE_ROOT"
fi

# Create the required subdirectories
echo "Creating subdirectories..."
mkdir -p "$QUEUE_ROOT/pending"
mkdir -p "$QUEUE_ROOT/done"
mkdir -p "$QUEUE_ROOT/failed"
mkdir -p "$QUEUE_ROOT/runtime"
mkdir -p "$QUEUE_ROOT/logs"

# Initialize the GPU status file
GPU_STATUS_FILE="$QUEUE_ROOT/runtime/gpu_status.json"
echo "Initializing GPU status file for $NUM_GPUS GPUs..."
JSON_CONTENT="{"
for (( i=0; i<$NUM_GPUS; i++ )); do
    JSON_CONTENT+="\"$i\": null"
    if [ $i -lt $(($NUM_GPUS-1)) ]; then
        JSON_CONTENT+=", "
    fi
done
JSON_CONTENT+="}"
echo "$JSON_CONTENT" > "$GPU_STATUS_FILE"

# Create an empty queue state file
QUEUE_STATE_FILE="$QUEUE_ROOT/runtime/queue_state.txt"
echo "Creating empty queue state file..."
touch "$QUEUE_STATE_FILE"

# Set permissions for the scripts in the current directory
chmod +x queue_manager.sh user_runner.sh queue_monitor.sh

echo -e "\n\e[32m✅ Installation complete!\e[0m"
echo "------------------------------------"
echo "Next steps:"
echo "1. Start the queue manager. For production, use the provided systemd service:"
echo "   sudo cp queue_manager.service /etc/systemd/system/"
echo "   sudo systemctl daemon-reload && sudo systemctl enable --now queue_manager.service"
echo "   Or for a simple test, run: nohup ./queue_manager.sh &"
echo ""
echo "2. (Optional) Add this scripts directory to user PATHs or create symlinks in /usr/local/bin for easy access."
echo "   Example: sudo ln -s \"$(pwd)/user_runner.sh\" /usr/local/bin/run_gpu_job"
