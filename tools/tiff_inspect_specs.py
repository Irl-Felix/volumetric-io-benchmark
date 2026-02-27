import os

import numpy as np
import tifffile as tiff


def inspect_tiff(path: str) -> None:
    print(f"\n📁 File: {path}")
    print("-" * 50)

    file_size = os.path.getsize(path)
    print(f"File size (GB): {file_size / (1024**3):.3f}")

    with tiff.TiffFile(path) as tif:
        pages = tif.pages
        first = pages[0]

        shape = first.shape
        dtype = first.dtype

        print(f"Number of pages (Z): {len(pages)}")
        print(f"Shape (per page): {shape}")
        print(f"Dtype: {dtype}")
        print(f"Bits per sample: {first.bitspersample}")

        compression = first.compression
        photometric = first.photometric
        planarconfig = first.planarconfig

        print(f"Compression: {compression.name if hasattr(compression, 'name') else compression}")
        print(f"Photometric: {photometric.name if hasattr(photometric, 'name') else photometric}")
        print(f"Planar config: {planarconfig.name if hasattr(planarconfig, 'name') else planarconfig}")

        try:
            arr = first.asarray()
            print(f"Is contiguous: {arr.flags['C_CONTIGUOUS']}")
        except Exception as e:
            print(f"Could not load array for contiguity check: {e}")

        bytes_per_pixel = first.bitspersample // 8
        slice_bytes = int(np.prod(shape)) * bytes_per_pixel
        print(f"Bytes per slice (MB): {slice_bytes / (1024**2):.2f}")

        total_bytes = slice_bytes * len(pages)
        print(f"Total image data (GB): {total_bytes / (1024**3):.2f}")

        print(f"Is BigTIFF: {tif.is_bigtiff}")
        print(f"Byte order: {tif.byteorder}")


def main() -> int:
    path = os.environ["MEDIOBENCH_TIFF_PATH"]
    inspect_tiff(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
