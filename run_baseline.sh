#!/bin/bash
# run_baseline.sh
# Measures disk ceiling (fio + dd) and memory bandwidth (stream)
# Then tells you exactly what to update in your benchmark scripts.

set -e

# Pick a Python interpreter. Some distros only ship `python3` (no `python` shim).
if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
else
    echo "ERROR: Python not found. Install Python 3 (e.g., 'sudo apt-get install -y python3')." >&2
    exit 127
fi

# Load shared config if present (exports MEDIOBENCH_* variables)
if [ -f "./config.env" ]; then
    set -a

    # If run directly (not via `make`), load config.env if present.
    if [ -f "config.env" ]; then
        set -a
        # shellcheck disable=SC1091
        source "config.env"
        set +a
    fi
    # shellcheck disable=SC1091
    DATA_PATH="${MEDIOBENCH_TIFF_PATH:?MEDIOBENCH_TIFF_PATH not set (set it in config.env)}"
    set +a
fi

DATA_PATH="${MEDIOBENCH_TIFF_PATH:?MEDIOBENCH_TIFF_PATH not set (set it in config.env)}"
RESULTS_DIR="results"
STREAM_BIN="bin/stream"

mkdir -p "$RESULTS_DIR"

echo "========================================"
echo " Hardware Baseline Measurement"
echo "========================================"

# ── 1. FIO ───────────────────────────────────
echo ""
echo "[1/3] Running fio (disk ceiling, direct I/O)..."
sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"

fio --name=seq-read \
    --filename="$DATA_PATH" \
    --rw=read \
    --bs=1M \
    --direct=1 \
    --numjobs=1 \
    --time_based \
    --runtime=30 \
    --output-format=normal \
    > "$RESULTS_DIR/fio_baseline.txt"

FIO_MIB=$(grep "bw=" "$RESULTS_DIR/fio_baseline.txt" | grep "READ:" | grep -oP 'bw=\K[0-9]+(?=MiB)')
FIO_GBS=$($PYTHON_BIN - <<PY
f = float("$FIO_MIB")
print(f"{f/1024:.2f}")
PY
)
echo "    fio result: ${FIO_MIB} MiB/s = ${FIO_GBS} GB/s"

# ── 2. DD ────────────────────────────────────
echo ""
echo "[2/3] Running dd (cold single-pass read)..."
sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"

DD_OUT=$(dd if="$DATA_PATH" of=/dev/null bs=4M 2>&1)
echo "$DD_OUT" > "$RESULTS_DIR/dd_baseline.txt"

# dd may report MB/s on slower disks; parse whatever it prints and convert to GB/s.
DD_GBS=$($PYTHON_BIN - <<PY
import re
import sys

s = """$DD_OUT"""

# Examples seen in the wild:
#   "1.5 GB/s", "129 MB/s", "950 kB/s", "800 MiB/s"
matches = re.findall(r"([0-9]+(?:\.[0-9]+)?)\s*([kKMGT]?i?B/s)", s)
if not matches:
    sys.stderr.write("ERROR: could not parse dd throughput from output:\n")
    sys.stderr.write(s + "\n")
    sys.exit(1)

value_str, unit = matches[-1]
value = float(value_str)
unit = unit.strip()

unit_upper = unit.upper()
is_iec = unit_upper.endswith("IB/S")

base = 1024.0 if is_iec else 1000.0
prefix = unit_upper[0] if unit_upper[0] != 'B' else ''

exp = {
    '': 0,
    'K': 1,
    'M': 2,
    'G': 3,
    'T': 4,
}.get(prefix)

if exp is None:
    sys.stderr.write(f"ERROR: unrecognized dd unit: {unit}\n")
    sys.exit(1)

bytes_per_sec = value * (base ** exp)
gb_per_sec = bytes_per_sec / 1e9
print(f"{gb_per_sec:.2f}")
PY
)

echo "    dd result: ${DD_GBS} GB/s"

# ── 3. STREAM ────────────────────────────────
echo ""
echo "[3/3] Running stream (compiled from tools/stream.c)..."

if [ ! -f "$STREAM_BIN" ]; then
    echo "    compiling stream..."
    gcc -O2 -o "$STREAM_BIN" tools/stream.c -lm
fi

"$STREAM_BIN" > "$RESULTS_DIR/stream_baseline.txt"

TRIAD=$(grep "Triad:" "$RESULTS_DIR/stream_baseline.txt" | awk '{print $2}')
TRIAD_GBS=$($PYTHON_BIN - <<PY
t = float("$TRIAD")
print(f"{t/1000:.1f}")
PY
)
echo "    stream Triad: ${TRIAD} MB/s = ${TRIAD_GBS} GB/s"

# ── SUMMARY ──────────────────────────────────
echo ""
echo "========================================"
echo " Results Summary"
echo "========================================"
echo "  fio  (disk, direct I/O): ${FIO_GBS} GB/s"
echo "  dd   (disk, cold pass):  ${DD_GBS} GB/s"
echo "  stream Triad (memory):   ${TRIAD_GBS} GB/s"
echo ""
echo "========================================"
echo " ACTION REQUIRED — update these constants"
echo "========================================"
echo ""
echo "  DISK_CEILING_GBS = ${DD_GBS}     <-- use dd cold value"
echo "  MEM_CEILING_GBS  = ${TRIAD_GBS}  <-- STREAM Triad reference"
echo ""
echo "  Update these in config.env:"
echo "    MEDIOBENCH_DISK_CEILING_GBS=${DD_GBS}"
echo "    MEDIOBENCH_MEM_CEILING_GBS=${TRIAD_GBS}"
echo ""
echo "  Raw outputs saved to: $RESULTS_DIR/"
echo "========================================"
