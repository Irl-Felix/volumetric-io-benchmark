import time
import os
import numpy as np
import tifffile as tiff

PATH            = os.environ["MEDIOBENCH_TIFF_PATH"]
N_RUNS          = int(os.environ["MEDIOBENCH_N_RUNS"])
MEM_CEILING_GBS = float(os.environ["MEDIOBENCH_MEM_CEILING_GBS"])
FILESIZE_GB     = float(os.environ["MEDIOBENCH_FILESIZE_GB"])


def warmup_page_cache(path: str, block_bytes: int = 8 * 1024 * 1024) -> None:
    # Best-effort warmup: stream the file once so the OS page cache is populated.
    with open(path, "rb") as f:
        while f.read(block_bytes):
            pass


warmup_page_cache(PATH)

times = []

for i in range(N_RUNS):
    t0  = time.perf_counter()
    try:
        arr = tiff.imread(PATH)
    except MemoryError as e:
        print(f"Condition:    Python + read  |  warm cache")
        print(f"Runs:         {N_RUNS}")
        print("Status:       SKIPPED (not enough RAM to materialize full volume)")
        print("Hint:         use the slice-by-slice benchmark (bench_read_slice_warm.py)")
        raise SystemExit(0) from e

    _ = int(arr.sum())
    t1  = time.perf_counter()
    times.append(t1 - t0)
    del arr

avg_t  = np.mean(times)
avg_gb = FILESIZE_GB / avg_t
std_t  = np.std(times)
std_gb = np.std([FILESIZE_GB / t for t in times])
pct    = (avg_gb / MEM_CEILING_GBS) * 100

print(f"Condition:    Python + read  |  warm cache")
print(f"Runs:         {N_RUNS}")
print(f"Elapsed:      avg={avg_t:.3f}s  std={std_t:.3f}s")
print(f"Throughput:   avg={avg_gb:.3f} GB/s  std={std_gb:.3f} GB/s")
print(f"% of ceiling: {pct:.1f}% of STREAM Triad")
