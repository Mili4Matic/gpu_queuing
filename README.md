# GPU Job Queueing System

A simple but robust system for managing and scheduling Python jobs on a shared server with multiple NVIDIA GPUs.

## Features

- **Fair Queueing**: Jobs are executed in a First-In, First-Out (FIFO) order.
- **Resource Isolation**: `CUDA_VISIBLE_DEVICES` is used to ensure a job can only access its assigned GPUs.
- **Automatic Environment Management**: Automatically activates the conda environment specified in the Python script.
- **Real-time Monitoring**: Users can see their position in the queue and view live job output.
- **Robustness**: The system is designed to recover from unexpected shutdowns of the manager.
- **Logging**: All job outputs are saved to log files for later inspection.

## Installation

1.  **Clone the Repository**:
    Place all the scripts from this project into a directory on your server, for example:
    `/home/linuxbida/Escritorio/VBoxTools/queue_jobs/scripts/`

2.  **Run the Installer**:
    Navigate to the scripts directory and run the installer. This will create the necessary directory structure and initialize the system files.

    ```bash
    cd /home/linuxbida/Escritorio/VBoxTools/queue_jobs/scripts/
    chmod +x *.sh
    ./install.sh
    ```

3.  **Add to PATH (Recommended)**:
    For convenience, add the `scripts` directory to your users' `PATH` or create symlinks to the scripts in `/usr/local/bin`.

    ```bash
    # For a single user (add to ~/.bashrc or ~/.zshrc)
    echo 'export PATH="/home/linuxbida/Escritorio/VBoxTools/queue_jobs/scripts:$PATH"' >> ~/.bashrc
    source ~/.bashrc

    # Or for all users (as root)
    sudo ln -s /home/linuxbida/Escritorio/VBoxTools/queue_jobs/scripts/user_runner.sh /usr/local/bin/run_gpu_job
    sudo ln -s /home/linuxbida/Escritorio/VBoxTools/queue_jobs/scripts/queue_monitor.sh /usr/local/bin/show_gpu_queue
    ```

## Usage

### 1. Prepare Your Python Script

Add a comment to the first line of your Python script specifying the conda environment to use.

```python
# conda_env: my_pytorch_env
import torch
import time
import os

# ... rest of your script
```

### 2. Submit a Job

Use the `user_runner.sh` (or the symlink `run_gpu_job`) to submit your script to the queue.

```bash
# Request 1 GPU
user_runner.sh --gpus 1 /path/to/your/script.py

# Request 2 GPUs
user_runner.sh --gpus 2 /path/to/your/script.py
```

The script will show you your position in the queue and wait. Once it's your turn, it will display the live output from your script. You can safely close the terminal; the job will continue running and its output will be saved in the `logs/` directory.

### 3. Monitor the Queue

Use `queue_monitor.sh` (or `show_gpu_queue`) to see the current status of the queue and GPU allocation.

```bash
queue_monitor.sh
```

### 4. Starting the Queue Manager

The `queue_manager.sh` script must be running in the background to process the queue.

**Method 1: Using `nohup` (Simple)**

```bash
nohup /home/linuxbida/Escritorio/VBoxTools/queue_jobs/scripts/queue_manager.sh &
```

**Method 2: Using `systemd` (Recommended for production)**

This ensures the manager restarts automatically if the server reboots.

```bash
# Copy the service file
sudo cp /home/linuxbida/Escritorio/VBoxTools/queue_jobs/scripts/queue_manager.service /etc/systemd/system/

# Reload the systemd daemon, enable, and start the service
sudo systemctl daemon-reload
sudo systemctl enable queue_manager.service
sudo systemctl start queue_manager.service

# Check its status
sudo systemctl status queue_manager.service
```