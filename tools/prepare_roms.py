#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Validate user-supplied Open Ice 1.21 ROMs and build the three Pocket assets.

Python 3.9+; standard library only. No network access and no ROM downloads.
"""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import zipfile
import zlib


def prepare(source, output, manifest=None):
    source, output = Path(source), Path(output)
    if manifest is None:
        manifest = json.loads(Path(__file__).with_name('roms.json').read_text())
    expected = manifest['roms']
    data = {}
    archive = None
    try:
        if source.is_file():
            archive = zipfile.ZipFile(source)
            members = {}
            for info in archive.infolist():
                name = Path(info.filename).name
                if info.is_dir() or name not in expected:
                    continue
                if name in members:
                    raise ValueError(f'Duplicate ROM in ZIP: {name}')
                members[name] = info
        elif not source.is_dir():
            raise ValueError(f'ROM directory or ZIP not found: {source}')
        for name, spec in expected.items():
            if archive is not None:
                info = members.get(name)
                if info is None:
                    raise ValueError(f'Missing ROM: {name} (revision 1.21 required)')
                if info.file_size != spec['size']:
                    raise ValueError(f'Incorrect ROM size: {name}')
                raw = archive.read(info)
            else:
                path = source / name
                if not path.is_file():
                    raise ValueError(f'Missing ROM: {name} (revision 1.21 required)')
                if path.stat().st_size != spec['size']:
                    raise ValueError(f'Incorrect ROM size: {name}')
                raw = path.read_bytes()
            actual = (len(raw), f'{zlib.crc32(raw):08x}', hashlib.sha1(raw).hexdigest())
            wanted = (spec['size'], spec['crc32'], spec['sha1'])
            if actual != wanted:
                raise ValueError(f'ROM checksum mismatch: {name}; expected revision 1.21')
            data[name] = raw
    finally:
        if archive is not None:
            archive.close()

    # Validate the complete set before creating any output or replacing a file.
    streams = {}
    for spec in manifest['streams']:
        raw = b''.join(data[name] for name in spec['parts'])
        if len(raw) != spec['size'] or hashlib.sha256(raw).hexdigest() != spec['sha256']:
            raise ValueError(f'Unexpected prepared stream: {spec["filename"]}')
        path = output / spec['filename']
        if path.exists() and path.read_bytes() != raw:
            raise FileExistsError(f'Refusing to replace different existing file: {path}')
        streams[spec['filename']] = raw
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.openice-', dir=output) as temp:
        for name, raw in streams.items():
            staged = Path(temp) / name
            staged.write_bytes(raw)
        for name in streams:
            destination = output / name
            if not destination.exists():
                (Path(temp) / name).replace(destination)
    return {name: hashlib.sha256(raw).hexdigest() for name, raw in streams.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='openice.zip or directory of extracted ROMs')
    parser.add_argument('--output', required=True, type=Path,
                        help='Destination Assets/openice/common directory on the SD card')
    args = parser.parse_args()
    try:
        results = prepare(args.source, args.output)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, RuntimeError) as error:
        parser.exit(1, f'Error: {error}\nNo replacement of existing different assets was performed.\n')
    print(f'Validated Open Ice 1.21; assets ready in {args.output}')
    for name, sha256 in results.items():
        print(f'{sha256}  {name}')


if __name__ == '__main__':
    main()
