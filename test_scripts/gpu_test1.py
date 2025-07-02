# conda_env my_env
import torch
import time

GPU_INDEX = 0
MATRIX_SIZE = 4096
REPS = 4000

device  = torch.device(f"cuda:{GPU_INDEX}")
torch.cuda.set_device(device)

print(f"Usando {GPU_INDEX}: {torch.cuda.get_device_name(device)}")
a = torch.randn((MATRIX_SIZE, MATRIX_SIZE), device=device)
b = torch.randn((MATRIX_SIZE, MATRIX_SIZE), device=device)

_ = torch.matmul(a, b)

torch.cuda.synchronize()
t0 = time.perf_counter()

for _ in range(REPS):
	_ = torch.matmul(a, b)

torch.cuda.synchronize()
elapsed = time.perf_counter() - t0

print(f"REPS{REPS}, time{elapsed}")


