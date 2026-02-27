import os

import tifffile


def main() -> int:
    path = os.environ["MEDIOBENCH_TIFF_PATH"]

    with tifffile.TiffFile(path) as tif:
        page = tif.pages[0]
        print(f"First page offset: {page.offset}")
        print(f"Data offset:       {page.dataoffsets[0]}")
        print(f"Byte count:        {page.databytecounts[0]}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
