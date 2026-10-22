#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Encode the supplied cover in the Pocket platform image format.

Optional artwork-only build step; requires Pillow. The ROM tool does not.
Format: https://www.analogue.co/developer/docs/openfpga/packaging-a-core
521x165, 16-bit monochrome, counter-clockwise pixel order, brightness first.
The entire portrait cover is fitted in the horizontal frame without cropping.
"""
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]


def main():
    source = ROOT / 'docs/images/openice-cover.jpg'
    cover = Image.open(source).convert('L')
    fitted = ImageOps.contain(cover, (521, 165), method=Image.Resampling.LANCZOS)
    canvas = Image.new('L', (521, 165), 0)
    canvas.paste(fitted, ((521 - fitted.width) // 2, (165 - fitted.height) // 2))
    pixels = canvas.load()
    # Same indexing used by Pocket Sync's renderBinImage decoder: right to left,
    # top to bottom within each column. Every second byte is zero.
    raw = bytearray()
    for x in range(520, -1, -1):
        for y in range(165):
            raw.extend((pixels[x, y], 0))
    output = ROOT / 'pocket/Platforms/_images/openice.bin'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(raw)
    # Decode independently through a 90-degree rotation to verify ordering.
    decoded = Image.frombytes('L', (165, 521), bytes(raw[0::2])).transpose(Image.Transpose.ROTATE_270)
    assert decoded.tobytes() == canvas.tobytes()
    preview = ROOT / 'build/openice-platform-preview.png'
    preview.parent.mkdir(exist_ok=True)
    decoded.save(preview)
    print(f'Wrote {output}: {len(raw)} bytes; round-trip pixels verified.')


if __name__ == '__main__':
    main()
