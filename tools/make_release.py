#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Create the ROM-free Pocket installation ZIP from an explicit file list."""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CORE = 'Cores/auricom79.OpenIce'


def release_files():
    files = {}
    for name in ('audio.json', 'core.json', 'data.json', 'input.json', 'interact.json',
                 'variants.json', 'video.json', 'bitstream.rbf_r'):
        files[f'{CORE}/{name}'] = (ROOT / 'pocket' / CORE / name).read_bytes()
    files['Platforms/openice.json'] = (ROOT / 'pocket/Platforms/openice.json').read_bytes()
    for name in ('prepare_roms.py', 'roms.json'):
        files[f'{CORE}/tools/{name}'] = (ROOT / 'tools' / name).read_bytes()
    for name in ('README.md', 'README.fr.md', 'BUILDING.md', 'MODIFICATIONS.txt', 'NOTICE.txt', 'LICENSE'):
        files[f'{CORE}/{name}'] = (ROOT / name).read_bytes()
    for path in sorted((ROOT / 'licenses').iterdir()):
        if path.is_file():
            files[f'{CORE}/licenses/{path.name}'] = path.read_bytes()
    files['Assets/openice/common/README.txt'] = (
        'Supply your own Open Ice revision 1.21 ROMs. No game ROMs are included.\n'
        'Use Cores/auricom79.OpenIce/tools/prepare_roms.py as described in the README.\n'
        'Expected outputs: openice-program.bin, openice-graphics.bin, openice-sound.bin.\n'
    ).encode()
    expected = json.loads((ROOT / 'source-manifest.json').read_text())['bitstream']['sha256']
    assert hashlib.sha256(files[f'{CORE}/bitstream.rbf_r']).hexdigest() == expected
    assert all(not name.endswith(('.bin', '.rom', '.hex')) for name in files)
    return files


def main():
    version = json.loads((ROOT / 'pocket' / CORE / 'core.json').read_text())['core']['metadata']['version']
    destination = ROOT / 'dist' / f'auricom79.OpenIce_{version}.zip'
    destination.parent.mkdir(exist_ok=True)
    files = release_files()
    with zipfile.ZipFile(destination, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, raw in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 20, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, raw)
    print(f'{hashlib.sha256(destination.read_bytes()).hexdigest()}  {destination}')
    print(f'{len(files)} files; no game ROMs included.')


if __name__ == '__main__':
    main()
