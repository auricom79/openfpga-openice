#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Encode the supplied title screenshot into the FPGA loading-screen bitmap.

Pillow is required only for this optional artwork build step. The source is
an already-rendered screenshot; no game program or graphics ROM is read.

The 180x114 five-bit grayscale bitmap uses one hexadecimal word per pixel,
in top-to-bottom, left-to-right order. The renderer doubles each pixel.
"""
import argparse
import hashlib
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def encode(source):
    with Image.open(source) as image:
        gray = image.convert('L')
    if gray.size != (400, 254):
        raise ValueError(f'Expected a 400x254 title screenshot; got {gray.size}')
    small = gray.resize((180, 114), Image.Resampling.LANCZOS)
    levels = [(value * 31 + 127) // 255 for value in small.tobytes()]
    assert len(levels) == 20520 and all(0 <= value <= 31 for value in levels)
    return ''.join(f'{value:02x}\n' for value in levels).encode('ascii')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path,
                        default=ROOT / 'docs/images/openice-title.png')
    parser.add_argument('--output', type=Path,
                        default=ROOT / 'src/rtl/openice_loading.hex')
    parser.add_argument('--quartus-output', type=Path,
                        default=ROOT / 'quartus/core/openice_loading.hex')
    parser.add_argument('--check', action='store_true',
                        help='Verify both encoded files without writing them')
    args = parser.parse_args()
    data = encode(args.source)
    for path in (args.output, args.quartus_output):
        if args.check:
            if not path.is_file() or path.read_bytes() != data:
                parser.error(f'Bitmap differs or is missing: {path}')
            print(f'Verified {path}')
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            print(f'Wrote {path}')
    print(f'20520 pixels, 5 bits per pixel; SHA-256 {hashlib.sha256(data).hexdigest()}')


if __name__ == '__main__':
    main()
