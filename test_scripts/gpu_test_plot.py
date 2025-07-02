# conda_env my_env
import torch
import time
import matplotlib.pyplot as plt

GPU_INDEX   = 0
MATRIX_SIZE = 4096
REPS        = 4000

device = torch.device(f"cuda:{GPU_INDEX}")
torch.cuda.set_device(device)

print(f"Using GPU {GPU_INDEX}: {torch.cuda.get_device_name(device)}")

# Create random matrices
a = torch.randn((MATRIX_SIZE, MATRIX_SIZE), device=device)
b = torch.randn((MATRIX_SIZE, MATRIX_SIZE), device=device)

# -------------------------------------------------------------------
# warm-up so the first measurement isn’t an outlier
_ = torch.matmul(a, b)
torch.cuda.synchronize()
# -------------------------------------------------------------------

# NEW: collect latency & plot
latencies = []

for _ in range(REPS):
    torch.cuda.synchronize()
    t0 = time.perf_counter()
    _ = torch.matmul(a, b)
    torch.cuda.synchronize()
    latencies.append(time.perf_counter() - t0)

total_time = sum(latencies)
print(f"REPS: {REPS}, total time: {total_time:.3f}s "
      f"(avg {total_time/REPS*1_000:.3f} ms per matmul)")

# Plot latencies
plt.figure(figsize=(8, 4))
plt.plot(latencies, linewidth=0.7)
plt.title(f"MatMul latency per iteration – {torch.cuda.get_device_name(device)}")
plt.xlabel("Iteration")
plt.ylabel("Time (s)")
plt.tight_layout()
plt.show()
