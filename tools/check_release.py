#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check source identity, relative project references and the ROM-free package."""
import hashlib
import json
from pathlib import Path
import re
import shlex
from make_release import release_files

ROOT = Path(__file__).resolve().parents[1]


def main():
    manifest = json.loads((ROOT / 'source-manifest.json').read_text())
    for name, expected in manifest['source_files'].items():
        assert hashlib.sha256((ROOT / 'src' / name).read_bytes()).hexdigest() == expected, name
    assert hashlib.sha256((ROOT / 'quartus/core/wolf_combined.v').read_bytes()).hexdigest() == manifest['generated_verilog']['public_sha256']
    assert hashlib.sha256((ROOT / 'quartus/core/core_constraints.sdc').read_bytes()).hexdigest() == manifest['constraints']['effective_quartus_sha256']
    for path in (ROOT / 'quartus').rglob('*'):
        if path.is_file():
            raw = path.read_bytes()
            assert b'/Users/' not in raw and b'/workspace/' not in raw, path
    qsf = (ROOT / 'quartus/ap_core.qsf').read_text()
    for line in qsf.splitlines():
        if re.match(r'set_global_assignment -name (VERILOG_FILE|SYSTEMVERILOG_FILE|QIP_FILE|SDC_FILE) ', line):
            relative = shlex.split(line)[-1]
            assert (ROOT / 'quartus' / relative).is_file(), relative
    files = release_files()
    core = json.loads(files['Cores/auricom79.OpenIce/core.json'])['core']
    assert core['metadata']['author'] == 'auricom79'
    assert core['metadata']['url'] == 'https://github.com/auricom79/openfpga-openice'
    for name, raw in files.items():
        if name.endswith('.json'):
            json.loads(raw)
        assert not name.startswith('/') and '..' not in Path(name).parts
    print(f'PASS: {len(manifest["source_files"])} exact source hashes, effective SDC, project references, ROM-free release ({len(files)} files).')


if __name__ == '__main__':
    main()
