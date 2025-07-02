# GPU Job Queueing System

A lightweight **Bash‑based scheduler** for running Python scripts on a shared machine with multiple NVIDIA GPUs. It provides fair queuing, robust resource isolation, automatic environment activation and self‑healing in case of crashes.

## Key Features

* **Concurrent dispatch** – jobs start as soon as enough free GPUs exist; no unnecessary serial blocking.
* **Fair FIFO queue** – first‑in‑first‑out order for jobs requesting the same amount of GPUs.
* **Resource isolation with `CUDA_VISIBLE_DEVICES`** – every process sees only the GPUs assigned to it.
* **Heartbeat + watchdog** – the runner touches a `.ready` file every *30 s*; the manager frees GPUs automatically if a heartbeat is missing for *≥ 2 min*.
* **Graceful cancellation** – press `Ctrl‑C` in the runner to abort the job; GPUs are released and the job is moved to `failed/`.
* **Automatic conda activation** – the runner reads `# conda_env: <name>` from the first line of your script and activates it.
* **Crash recovery** – on start‑up the manager cleans up stale locks and frees GPUs that were left busy.
* **Real‑time logs** – live output is streamed to your terminal and recorded under `opt/queue_jobs/logs/`.
Also includes a 'queue_monitor.sh' where the user can monitor live queue state
* **Portable** – zero external dependencies beyond Bash, Python ≥3.8 and NVIDIA drivers/CUDA.

## Directory Layout

```
opt/queue_jobs/
├── pending/            # staging area while a job waits
├── done/               # successful jobs are moved here
├── failed/             # jobs that exited with non‑zero code or were aborted
├── logs/               # stdout/err of every job (rotated externally)
└── runtime/
    ├── queue_state.txt # the FIFO queue
    ├── gpu_status.json # which job owns each GPU id
    ├── *.ready         # per‑job control files touched by the heartbeat
    └── .manager.lock   # prevents two managers from running
```

## Installation

1. **Clone / copy** the repository to the server, e.g.

   ```bash
   /opt/gpu_queue/
   ```

2. **Run the installer**

   ```bash
   cd /opt/gpu_queue
   chmod +x *.sh
   ./install.sh
   ```

   This creates the `opts/queue_jobs/` tree and initialises `gpu_status.json` with one entry per GPU detected by `nvidia-smi`.

3. **Add scripts to your PATH (optional)**

   ```bash
   sudo ./wrap_installer.sh
   ```
   Make sure that you have already runned ./install.sh, and routes on wrap_installer.sh are correct.
   This should enable all users on the system to add scripts to the queue using `gpurunner` and monitor the queue with `gpuqueue`.

## Starting the Queue Manager

Launch the daemon once per host:

### Quick & dirty

```bash
nohup /opt/gpu_queue/queue_manager.sh &
```

### Production (systemd)

```bash
sudo cp /opt/gpu_queue/queue_manager.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now queue_manager.service
```

Verify with `systemctl status queue_manager.service`.

## Submitting a Job

1. **Annotate the script**

```python
# conda_env my_env
import torch, time
...
```

2. **Send to queue**

```bash
run_gpu_job --gpus 1 /path/to/script.py  # request 1 GPU
run_gpu_job --gpus 2 /path/to/script.py  # request 2 GPUs
```

The runner will:

1. create a unique job id under `pending/<user>/`,
2. append it to the queue,
3. wait displaying a spinner and queue position,
4. start as soon as GPUs are available,
5. stream output and write `logs/<JOB_ID>.log`.

Press **Ctrl‑C** at any time to cancel; the job will be marked failed and resources freed.

## Monitoring

```bash
show_gpu_queue                # textual snapshot
tail -f dam/queue_jobs/logs/<JOB_ID>.log   # live log
```

## Configuration knobs

All tunables live at the top of the corresponding script:

| Script             | Variable         | Default | Meaning                                                |
| ------------------ | ---------------- | ------- | ------------------------------------------------------ |
| `queue_manager.sh` | `STALE_MINUTES`  | `1`     | time without heartbeat before a job is considered dead |
|                    | `SLEEP_IDLE`     | `5`     | seconds to sleep when queue empty                      |
| `user_runner.sh`   | `HEARTBEAT_SECS` | `30`    | interval between `touch` operations on `.ready`        |

## Cancelling jobs without terminal

If you lost the original shell, simply delete the `.ready` file:

```bash
rm opt/queue_jobs/runtime/<JOB_ID>.ready
```

The watchdog will notice within two minutes and clean everything up.

A CLI helper `queue_cancel.sh` is planned.

## Troubleshooting

| Symptom                                              | Likely cause / fix                                                              |
| ---------------------------------------------------- | ------------------------------------------------------------------------------- |
| Job never starts, queue position stays “1”           | No free GPU with enough memory – check `nvidia-smi`.                            |
| Job vanishes from queue, marked *failed* immediately | Your script exited with non‑zero code (see its `.log`).                         |
| GPUs show as used but no process visible             | Manager stopped while job running → restart manager; it will recover in ≤2 min. |

## License

MIT

---

*This README reflects the queue version with heartbeat support and automatic stale‑job cleanup.*
