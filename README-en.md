# Characterizing I/O Bottlenecks in Volumetric Medical Image Loading Pipelines

Benchmarks for **page cache aware, low copy data loading** of volumetric medical image stacks: how fast a large image stack can be loaded from storage into memory under different cache conditions.

Current focus: **multi-page TIFF stacks** (common in microscopy / volumetric imaging workflows), measured with both Python and C implementations.

## What it measures

- Latency (seconds): average + standard deviation over repeated runs
- Throughput (GB/s): effective data rate from file size and elapsed time
- Cold vs warm behavior:
  - cold-cache: drop Linux page cache to force disk I/O
  - warm-cache: allow OS page cache to represent repeated access
- Access-path differences:
  - `read()` (copy into user buffer)
  - `mmap()` (map file pages and touch bytes in-place)

## Motivation

Medical image stacks are often multi-GB files. Depending on whether the data is already in the OS page cache, performance can be limited by:

- storage bandwidth (cold reads)
- memory bandwidth and copy costs (warm reads)
- per-slice overhead / format decode overhead (Python libraries, page iteration)

For deep learning input pipelines, this translates into a practical question: are you bottlenecked on the cold path (I/O) or the warm path (memory/copy/decode), and does using `mmap()` actually reduce the dominant cost for your workload?

This repo makes those differences visible with minimal, reproducible benchmarks.

## Quickstart

1) Create your local config:

```bash
make init
```

2) Edit `config.env` and set at least:

- `MEDIOBENCH_TIFF_PATH` (path to your TIFF)

3) Install Python deps:

```bash
python3 -m pip install -r requirements.txt
```

4) Autofill TIFF derived constants (file size + slice layout):

```bash
set -a; source config.env; set +a
python3 tools/derive_config.py
```

Copy the printed `MEDIOBENCH_FILESIZE_GB`, `MEDIOBENCH_N_SLICES`, `MEDIOBENCH_SLICE_BYTES`, `MEDIOBENCH_DATA_OFFSET` into `config.env`.

5) (Recommended) Install baseline tools, run baseline, update ceilings:

- Install `fio` using your package manager (baseline needs `fio`). `dd` is usually already installed (coreutils).

Example (Ubuntu/Debian):

```bash
sudo apt-get update
sudo apt-get install -y fio
```

Run baseline (builds STREAM from `tools/stream.c` as `bin/stream`):

```bash
make baseline
```

Then copy the suggested values into `config.env`:

- `MEDIOBENCH_DISK_CEILING_GBS` (from `dd` cold pass)
- `MEDIOBENCH_MEM_CEILING_GBS`  (from STREAM Triad reference)

6) Build and run:

```bash
make
make run-cold
make run-warm
```

## Tools

These are helpers (not benchmarks):

- `python tools/derive_config.py` prints suggested `config.env` values (file size + slice layout)
- `python tools/tiff_layout_info.py` prints page data offsets/byte counts (useful for layout debugging)
- `python tools/tiff_inspect_specs.py` prints basic TIFF metadata and derived sizes

## Baseline (optional but recommended)

`make baseline` measures your machine’s ceilings:

- Disk read ceiling (fio direct I/O + dd cold pass)
- Memory bandwidth ceiling (STREAM)

Requirements:

- `fio` installed (for direct I/O disk baseline)
- `dd` (usually preinstalled as part of coreutils)
- Python 3 (`python3`) (used for simple parsing/unit conversions)
- a C compiler (gcc/clang) to build STREAM from `tools/stream.c`

For reproducibility, this repo vendors the STREAM reference implementation in tools/stream.c, and `make baseline` builds it as `bin/stream` before running it.

By default, STREAM is built single-threaded. If you want OpenMP (and your toolchain supports it), run:
```bash
make STREAM_OPENMP=1 baseline
```

```bash
make baseline
```

Then update these in `config.env`:

- `MEDIOBENCH_DISK_CEILING_GBS`
- `MEDIOBENCH_MEM_CEILING_GBS`

`MEDIOBENCH_MEM_CEILING_GBS` is based on STREAM Triad, which is a useful reference but not a strict upper bound for every access pattern (so some read-only workloads can show >100%).

Note: baseline uses `sudo` to drop caches and expects `fio` to be installed.

## What you need to provide

This repo does **not** ship a sample TIFF (files are often large and/or not redistributable). To run the benchmarks, point `MEDIOBENCH_TIFF_PATH` to:

- your own TIFF stack, or
- a publicly redistributable sample TIFF you download separately.

If you want a conventional place to put local test files, you can drop them under `data/` and set `MEDIOBENCH_TIFF_PATH=data/your_file.tif`. The `data/` directory is gitignored so you don’t accidentally commit large/private datasets.

## System requirements (rule of thumb)

RAM needs depend more on the **decoded volume size** than the TIFF file size on disk.

- Full-volume Python decode (`tifffile.imread`) materializes the entire volume in RAM.
  - Minimum (may still be tight): ~1.5× decoded volume size
  - Recommended: ~2–3× decoded volume size
- Slice-by-slice benchmarks only need memory for a single slice (and are suitable for low-RAM machines).

Other practical requirements:

- Cold-cache runs require `sudo` access to drop Linux page cache.
- Baseline requires `fio`, `dd`, Python 3, and a C compiler.

## Notes / limitations

- Cold-cache benchmarks require permission to run `sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'`.
- The Python full-volume `tifffile.imread()` benchmarks materialize the entire decoded volume in RAM. On low-RAM machines this may fail; use the slice-by-slice benchmarks instead.
- The C `*_slice_*` benchmarks assume the TIFF pages are stored in a simple contiguous layout (constant slice byte count and `offset = DATA_OFFSET + i*SLICE_BYTES`).
  `python tools/derive_config.py` warns if this is not true.
