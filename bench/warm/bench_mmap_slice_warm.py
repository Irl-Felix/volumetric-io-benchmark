import time
import mmap
import os
import numpy as np

PATH            = os.environ["MEDIOBENCH_TIFF_PATH"]
N_RUNS          = int(os.environ["MEDIOBENCH_N_RUNS"])
N_SLICES        = int(os.environ["MEDIOBENCH_N_SLICES"])
SLICE_BYTES     = int(os.environ["MEDIOBENCH_SLICE_BYTES"])
DATA_OFFSET     = int(os.environ["MEDIOBENCH_DATA_OFFSET"])
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
    t0 = time.perf_counter()

    with open(PATH, "rb") as f:
        mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)

        for s in range(N_SLICES):
            offset = DATA_OFFSET + s * SLICE_BYTES
            raw    = mm[offset : offset + SLICE_BYTES]
            arr    = np.frombuffer(raw, dtype=np.uint16)
            _      = arr[0]

        mm.close()

    t1 = time.perf_counter()
    times.append(t1 - t0)

avg_t  = np.mean(times)
avg_gb = FILESIZE_GB / avg_t
std_t  = np.std(times)
std_gb = np.std([FILESIZE_GB / t for t in times])
pct    = (avg_gb / MEM_CEILING_GBS) * 100

print(f"Condition:    Python + mmap  |  warm cache  |  slice-by-slice")
print(f"Slices:       {N_SLICES}")
print(f"Runs:         {N_RUNS}")
print(f"Elapsed:      avg={avg_t:.3f}s  std={std_t:.3f}s")
print(f"Throughput:   avg={avg_gb:.3f} GB/s  std={std_gb:.3f} GB/s")
print(f"% of ceiling: {pct:.1f}% of STREAM Triad")
