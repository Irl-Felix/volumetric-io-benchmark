import time
import mmap
import subprocess
import os
import numpy as np

PATH             = os.environ["MEDIOBENCH_TIFF_PATH"]
N_RUNS           = int(os.environ["MEDIOBENCH_N_RUNS"])
DISK_CEILING_GBS = float(os.environ["MEDIOBENCH_DISK_CEILING_GBS"])
FILESIZE_GB      = float(os.environ["MEDIOBENCH_FILESIZE_GB"])

def drop_cache():
    subprocess.run(
        ["sudo", "sh", "-c", "echo 3 > /proc/sys/vm/drop_caches"],
        check=True
    )

times = []

for i in range(N_RUNS):
    drop_cache()
    t0 = time.perf_counter()

    with open(PATH, "rb") as f:
        mm  = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        arr = np.frombuffer(mm, dtype=np.uint16)
        _   = int(arr.sum())   # force every page to be touched
        del arr                # release mmap reference before closing
        mm.close() 

    t1 = time.perf_counter()
    times.append(t1 - t0)

avg_t  = np.mean(times)
avg_gb = FILESIZE_GB / avg_t
std_t  = np.std(times)
std_gb = np.std([FILESIZE_GB / t for t in times])
pct    = (avg_gb / DISK_CEILING_GBS) * 100

print(f"Condition:    Python + mmap  |  cold cache")
print(f"Runs:         {N_RUNS}")
print(f"Elapsed:      avg={avg_t:.3f}s  std={std_t:.3f}s")
print(f"Throughput:   avg={avg_gb:.3f} GB/s  std={std_gb:.3f} GB/s")
print(f"% of ceiling: {pct:.1f}% of disk max")