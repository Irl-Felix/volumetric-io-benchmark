> English ONLY available in [README-en.md](README-en.md)

# Characterizing I/O Bottlenecks in Volumetric Medical Image Loading Pipelines /  體積式醫學影像載入流程中的 I/O 瓶頸分析

Benchmarks for **page cache aware, low copy data loading** of volumetric medical image stacks.  
針對**具備 page cache 意識與低拷貝資料載入**的體積式醫學影像堆疊進行效能基準測試。

Goal: understand how fast a large image stack can be loaded from storage into memory under different cache conditions.  
目標：分析在不同 cache 狀態下，大型影像資料從儲存裝置載入記憶體的速度。

Current focus: **multi-page TIFF stacks**（顯微鏡 / volumetric imaging 常見格式），並同時提供 Python 與 C 實作測試。

---

## What it measures / 測量項目

- Latency（延遲，秒）: average + standard deviation over repeated runs  
- Throughput（吞吐量，GB/s）: 根據檔案大小與時間計算有效資料速率  
- Cold vs warm behavior（冷 / 熱 cache 行為）
  - cold-cache：清除 Linux page cache 強制磁碟 I/O
  - warm-cache：利用 OS page cache 模擬重複存取
- Access path differences（資料存取路徑差異）
  - `read()`：複製到 user buffer
  - `mmap()`：直接映射檔案頁面並觸發存取

---

## Motivation / 研究動機

Medical image stacks are often multi-GB files.  

Performance may be limited by：

- storage bandwidth（冷讀取時受磁碟頻寬限制）
- memory bandwidth & copy cost（熱讀取時受記憶體與 copy 成本限制）
- per-slice overhead / decode overhead（Python library / page iteration 等）

對深度學習 pipeline 的核心問題：

目前 bottleneck 在 cold path（I/O）還是 warm path（memory / copy / decode）？  
使用 `mmap()` 是否真的降低主要成本？

This repo provides minimal and reproducible benchmarks to make these differences visible.  
此 repo 提供可重現的最小 benchmark 來觀察這些差異。

---

## Quickstart / 快速開始

1) Create local config  (建立本地設定)：

```bash
make init
```

2) Edit `config.env`  (至少設定)：

- `MEDIOBENCH_TIFF_PATH`（TIFF 路徑）

3) Install Python dependencies  (安裝 Python 套件)：

```bash
python3 -m pip install -r requirements.txt
```

4) Autofill derived constants  (自動推導 TIFF 相關參數)：

```bash
set -a; source config.env; set +a
python3 tools/derive_config.py
```

將輸出的值填入 `config.env`：

- `MEDIOBENCH_FILESIZE_GB`
- `MEDIOBENCH_N_SLICES`
- `MEDIOBENCH_SLICE_BYTES`
- `MEDIOBENCH_DATA_OFFSET`

5) (Recommended) Install baseline tools, run baseline, update ceilings  （建議：安裝 baseline 工具、量測上限、更新參數）：

- Install `fio` using your package manager (baseline needs `fio`). `dd` is usually already installed (coreutils).  
  安裝 `fio`（baseline 需要）。`dd` 通常已內建（coreutils）。

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

- `MEDIOBENCH_DISK_CEILING_GBS`  (from `dd` cold pass)
- `MEDIOBENCH_MEM_CEILING_GBS`   (from STREAM Triad reference)

6) Build and run (建置與執行)：

```bash
make
make run-cold
make run-warm
```

---

## Tools / 工具

輔助工具（非 benchmark）：

- `derive_config.py`：推導 config 參數（檔案大小 / slice layout）
- `tiff_layout_info.py`：顯示 page offset / byte count（layout debug）
- `tiff_inspect_specs.py`：顯示 TIFF metadata 與推導尺寸

---

## Baseline (optional but recommended) / (建議但非必要)

`make baseline` 量測系統上限：

- Disk read ceiling（fio + dd 冷讀）
- Memory bandwidth ceiling（STREAM）

Requirements / 需求：

- `fio` installed (for direct I/O disk baseline)
- `dd` (usually preinstalled as part of coreutils)
- Python 3 (`python3`) (used for simple parsing/unit conversions)
- a C compiler (gcc/clang) to build STREAM from `tools/stream.c`

此 repo 內含 STREAM reference implementation（tools/stream.c），`make baseline` 會自動建置為 `bin/stream`。

預設為單執行緒。若要 OpenMP：

```bash
make STREAM_OPENMP=1 baseline
```

然後更新 `config.env`：

- `MEDIOBENCH_DISK_CEILING_GBS`
- `MEDIOBENCH_MEM_CEILING_GBS`

STREAM Triad 是參考值，不一定是所有 workload 的嚴格上限。

Note：baseline 需要 `sudo`（用於 drop caches）與 `fio`。

---

## What you need to provide / 使用者需提供

This repo does **not** ship a sample TIFF (files are often large and/or not redistributable). To run the benchmarks, point `MEDIOBENCH_TIFF_PATH` to:

- your own TIFF stack, or
- a publicly redistributable sample TIFF you download separately.

If you want a conventional place to put local test files, you can drop them under `data/` and set `MEDIOBENCH_TIFF_PATH=data/your_file.tif`. The `data/` directory is gitignored so you don’t accidentally commit large/private datasets.

## System requirements (rule of thumb)  // 系統需求（概略）

RAM 需求通常取決於 **解碼後的體積資料大小**（decoded volume size），而不只是 TIFF 在磁碟上的檔案大小。

- Full-volume Python decode（`tifffile.imread`）會把整個 volume 直接 materialize 到 RAM。
  - 最低（可能仍偏緊）：約為 decoded volume size 的 ~1.5×
  - 建議：decoded volume size 的 ~2–3×
- Slice-by-slice benchmarks 只需要單張 slice 的記憶體（適合低 RAM 機器）。

其他常見需求：

- Cold-cache 需要 `sudo` 權限來 drop Linux page cache。
- Baseline 需要 `fio`、`dd`、Python 3，以及 C compiler。

## Notes / limitations  // 注意事項與限制

- Cold-cache benchmarks require permission to run `sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'`.
- The Python full-volume `tifffile.imread()` benchmarks materialize the entire decoded volume in RAM. On low-RAM machines this may fail; use the slice-by-slice benchmarks instead.
- The C `*_slice_*` benchmarks assume the TIFF pages are stored in a simple contiguous layout (constant slice byte count and `offset = DATA_OFFSET + i*SLICE_BYTES`).
  `python tools/derive_config.py` warns if this is not true.

