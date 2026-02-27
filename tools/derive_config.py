import os
import sys

import tifffile as tiff


def die(msg: str, code: int = 2) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(code)


def main() -> int:
    path = os.environ.get("MEDIOBENCH_TIFF_PATH")
    if not path:
        die("Missing MEDIOBENCH_TIFF_PATH. Set it (usually in config.env) and retry.")

    if not os.path.exists(path):
        die(f"TIFF not found: {path}")

    file_size_bytes = os.path.getsize(path)
    file_size_gb = file_size_bytes / (1024**3)

    with tiff.TiffFile(path) as tif:
        pages = list(tif.pages)
        if not pages:
            die("TIFF has no pages")

        data_offsets = []
        byte_counts = []
        for p in pages:
            if not hasattr(p, "dataoffsets") or not hasattr(p, "databytecounts"):
                die("TIFF page missing data offsets/byte counts; cannot derive slice layout")
            data_offsets.append(int(p.dataoffsets[0]))
            byte_counts.append(int(p.databytecounts[0]))

        n_slices = len(pages)
        slice_bytes = byte_counts[0]
        data_offset = data_offsets[0]

        contiguous = True
        constant_sizes = all(b == slice_bytes for b in byte_counts)
        if not constant_sizes:
            contiguous = False

        if contiguous:
            for i in range(1, n_slices):
                if data_offsets[i] != data_offset + i * slice_bytes:
                    contiguous = False
                    break

    print("# Suggested values for config.env")
    print(f"MEDIOBENCH_FILESIZE_GB={file_size_gb:.6f}")
    print(f"MEDIOBENCH_N_SLICES={n_slices}")
    print(f"MEDIOBENCH_SLICE_BYTES={slice_bytes}")
    print(f"MEDIOBENCH_DATA_OFFSET={data_offset}")

    if not contiguous:
        print(
            "# WARNING: Page data is not a simple contiguous (offset + i*slice_bytes) layout.\n"
            "# The C *_slice_* benchmarks assume contiguity and may not be valid for this TIFF.\n"
            "# The Python slice benchmarks should still work.\n",
            file=sys.stderr,
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())