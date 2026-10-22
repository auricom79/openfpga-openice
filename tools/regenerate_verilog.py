#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Regenerate the combined HDL using sv2v 0.0.13; do not run Quartus."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sv2v', default='sv2v')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/wolf_combined.v')
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'source-manifest.json').read_text())
    command = [args.sv2v, *['-D' + name for name in manifest['defines']],
               '-I' + str(ROOT / 'src/upstream/wolf-unit/rtl/dcs'),
               *[str(ROOT / 'src' / name) for name in manifest['compile_order']]]
    result = subprocess.run(command, stdout=subprocess.PIPE, check=True)
    # sv2v embeds diagnostic source filenames. Match the public relative form.
    raw = result.stdout.replace((str(ROOT / 'src') + '/').encode(), b'src/')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(raw)
    actual = hashlib.sha256(raw).hexdigest()
    expected = manifest['generated_verilog']['public_sha256']
    print(f'{actual}  {args.output}')
    if actual != expected:
        raise SystemExit('Generated HDL differs from the release snapshot; review before compiling.')
    print('PASS: generated HDL matches the published release snapshot.')


if __name__ == '__main__':
    main()
