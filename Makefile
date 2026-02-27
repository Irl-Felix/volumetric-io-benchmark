CC      = gcc
CFLAGS  = -O2 -Wall -I.
LIBS    = -lm

.DEFAULT_GOAL := all

# Python interpreter selection.
# Many modern distros ship only `python3` (no `python` symlink).
PYTHON := $(shell if command -v python >/dev/null 2>&1; then echo python; \
			   elif command -v python3 >/dev/null 2>&1; then echo python3; \
			   else echo python; fi)

# Load shared config (env-style KEY=VALUE).
# This is the single source of truth for paths/ceilings/layout.
#
# Allow bootstrapping targets to run without config.env.
BOOTSTRAP_GOALS := init help clean
BOOTSTRAP_GOALS += all
ifneq (,$(filter $(BOOTSTRAP_GOALS),$(MAKECMDGOALS)))
	# no config required
else
	ifeq (,$(wildcard config.env))
		$(error Missing config.env. Run: make init (or copy config.env.example to config.env))
	endif
	include config.env
	export
endif

# Ensure repo-root Python modules are importable by bench scripts.
export PYTHONPATH := $(CURDIR)

BIN_DIR  = bin
COLD_DIR = bench/cold
WARM_DIR = bench/warm

# STREAM baseline build options
# - Default: build single-threaded and avoid noisy warnings from vendored STREAM.
# - Optional: `make STREAM_OPENMP=1 baseline` to compile+link with OpenMP.
STREAM_OPENMP ?= 0
STREAM_CFLAGS  = $(CFLAGS) -Wno-unknown-pragmas -Wno-unused-but-set-variable
STREAM_LIBS    = $(LIBS)
ifeq ($(STREAM_OPENMP),1)
STREAM_CFLAGS += -fopenmp
STREAM_LIBS   += -fopenmp
endif

C_COLD = \
	bench_read_cold \
	bench_mmap_cold \
	bench_read_slice_cold \
	bench_mmap_slice_cold

C_WARM = \
	bench_read_warm \
	bench_mmap_warm \
	bench_read_slice_warm \
	bench_mmap_slice_warm

.PHONY: all clean baseline run-cold run-warm help init check-config

check-config:
	@test -n "$(MEDIOBENCH_TIFF_PATH)" || (echo "ERROR: MEDIOBENCH_TIFF_PATH is not set. Edit config.env (or run: make init)" >&2; exit 2)
	@test -n "$(MEDIOBENCH_N_RUNS)" || (echo "ERROR: MEDIOBENCH_N_RUNS is not set in config.env" >&2; exit 2)
	@test -n "$(MEDIOBENCH_FILESIZE_GB)" || (echo "ERROR: MEDIOBENCH_FILESIZE_GB is not set in config.env (run: python3 tools/derive_config.py)" >&2; exit 2)
	@test -n "$(MEDIOBENCH_DISK_CEILING_GBS)" || (echo "ERROR: MEDIOBENCH_DISK_CEILING_GBS is not set in config.env (run: make baseline)" >&2; exit 2)
	@test -n "$(MEDIOBENCH_MEM_CEILING_GBS)" || (echo "ERROR: MEDIOBENCH_MEM_CEILING_GBS is not set in config.env (run: make baseline)" >&2; exit 2)
	@test -n "$(MEDIOBENCH_N_SLICES)" || (echo "ERROR: MEDIOBENCH_N_SLICES is not set in config.env (run: python3 tools/derive_config.py)" >&2; exit 2)
	@test -n "$(MEDIOBENCH_SLICE_BYTES)" || (echo "ERROR: MEDIOBENCH_SLICE_BYTES is not set in config.env (run: python3 tools/derive_config.py)" >&2; exit 2)
	@test -n "$(MEDIOBENCH_DATA_OFFSET)" || (echo "ERROR: MEDIOBENCH_DATA_OFFSET is not set in config.env (run: python3 tools/derive_config.py)" >&2; exit 2)

init:
	@test -f config.env || cp config.env.example config.env
	@echo "Created config.env (edit it before running benchmarks)."

all: $(addprefix $(BIN_DIR)/, $(C_COLD)) $(addprefix $(BIN_DIR)/, $(C_WARM))

$(BIN_DIR)/bench_read_cold:       $(COLD_DIR)/bench_read_cold.c       | $(BIN_DIR)
	$(CC) $(CFLAGS) -o $@ $< $(LIBS)

$(BIN_DIR)/bench_mmap_cold:       $(COLD_DIR)/bench_mmap_cold.c       | $(BIN_DIR)
	$(CC) $(CFLAGS) -o $@ $< $(LIBS)

$(BIN_DIR)/bench_read_slice_cold: $(COLD_DIR)/bench_read_slice_cold.c | $(BIN_DIR)
	$(CC) $(CFLAGS) -o $@ $< $(LIBS)

$(BIN_DIR)/bench_mmap_slice_cold: $(COLD_DIR)/bench_mmap_slice_cold.c | $(BIN_DIR)
	$(CC) $(CFLAGS) -o $@ $< $(LIBS)

$(BIN_DIR)/bench_read_warm:       $(WARM_DIR)/bench_read_warm.c       | $(BIN_DIR)
	$(CC) $(CFLAGS) -o $@ $< $(LIBS)

$(BIN_DIR)/bench_mmap_warm:       $(WARM_DIR)/bench_mmap_warm.c       | $(BIN_DIR)
	$(CC) $(CFLAGS) -o $@ $< $(LIBS)

$(BIN_DIR)/bench_read_slice_warm: $(WARM_DIR)/bench_read_slice_warm.c | $(BIN_DIR)
	$(CC) $(CFLAGS) -o $@ $< $(LIBS)

$(BIN_DIR)/bench_mmap_slice_warm: $(WARM_DIR)/bench_mmap_slice_warm.c | $(BIN_DIR)
	$(CC) $(CFLAGS) -o $@ $< $(LIBS)

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

# ── baseline ─────────────────────────────────
$(BIN_DIR)/stream: tools/stream.c | $(BIN_DIR)
	$(CC) $(STREAM_CFLAGS) -o $@ $< $(STREAM_LIBS)

baseline: $(BIN_DIR)/stream
	@bash run_baseline.sh

# ── run targets ───────────────────────────────
run-cold: check-config $(addprefix $(BIN_DIR)/, $(C_COLD))
	@echo "=== Cold cache benchmarks ==="
	$(PYTHON) $(COLD_DIR)/bench_read_cold.py
	$(PYTHON) $(COLD_DIR)/bench_mmap_cold.py
	$(PYTHON) $(COLD_DIR)/bench_read_slice_cold.py
	$(PYTHON) $(COLD_DIR)/bench_mmap_slice_cold.py
	$(BIN_DIR)/bench_read_cold
	$(BIN_DIR)/bench_mmap_cold
	$(BIN_DIR)/bench_read_slice_cold
	$(BIN_DIR)/bench_mmap_slice_cold

run-warm: check-config $(addprefix $(BIN_DIR)/, $(C_WARM))
	@echo "=== Warm cache benchmarks ==="
	$(PYTHON) $(WARM_DIR)/bench_read_warm.py
	$(PYTHON) $(WARM_DIR)/bench_mmap_warm.py
	$(PYTHON) $(WARM_DIR)/bench_read_slice_warm.py
	$(PYTHON) $(WARM_DIR)/bench_mmap_slice_warm.py
	$(BIN_DIR)/bench_read_warm
	$(BIN_DIR)/bench_mmap_warm
	$(BIN_DIR)/bench_read_slice_warm
	$(BIN_DIR)/bench_mmap_slice_warm

# ── clean ─────────────────────────────────────
clean:
	rm -rf $(BIN_DIR)
	rm -f results/fio_baseline.txt \
	      results/dd_baseline.txt \
	      results/stream_baseline.txt

help:
	@echo "Usage:"
	@echo "  make           — compile all C benchmarks"
	@echo "  make baseline  — measure disk + memory hardware ceilings"
	@echo "  make run-cold  — run all cold cache benchmarks"
	@echo "  make run-warm  — run all warm cache benchmarks"
	@echo "  make clean     — remove binaries and baseline results"

