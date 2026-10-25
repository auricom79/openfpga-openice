#!/usr/bin/env python3
"""Run synthetic loading, APF, display and memory/CPU RTL tests with Verilator.

No game ROMs, Quartus installation or FPGA are required. The display integration
uses the actual wrapper, loader, command handler and video/audio RTL with mock
PLL, arcade system and PSRAM peripherals, and three 4KiB synthetic asset slots.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verilator', default=os.environ.get('VERILATOR', 'verilator'))
    parser.add_argument('--full', action='store_true', help='Also transfer all 21 MiB of synthetic asset bytes')
    parser.add_argument('--images', action='store_true', help='Verify captured loading artwork/bar/digits pixel by pixel (requires Pillow)')
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--only', choices=['loader', 'apf', 'display', 'loading', 'performance', 'ram', 'rom-cache', 'gfx-stream-burst'])
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    if args.images and args.only not in (None, 'loading'):
        parser.error('--images requires --only loading or no --only selection')
    executable = shutil.which(args.verilator)
    if executable is None:
        parser.error('Verilator not found; install it or pass --verilator /path/to/verilator')
    rtl = ROOT / 'src/rtl'
    tests = ROOT / 'tests/rtl'
    common = [ROOT / 'quartus/core/core_bridge_cmd.v', ROOT / 'quartus/apf/common.v',
              tests / 'display_datatable.sv']
    adapter = ROOT / 'src/upstream/wolf-unit/rtl/yunit/yunit_mem_cdc.sv'
    ram = ROOT / 'src/upstream/wolf-unit/rtl/wolf/ram_sdram.sv'
    sdram = ROOT / 'src/upstream/wolf-unit/rtl/sdram'
    tms = ROOT / 'src/upstream/wolf-unit/rtl/tms34010/rtl'
    package = tms / 'tms34010_pkg.sv'
    tms_sources = [package, *sorted(path for path in tms.rglob('*.sv') if path != package)]
    cases = [
        ('loading', 'tb_loading', [], [rtl / 'wolf_pocket_loading.sv']),
        ('loader', 'tb_loader_4k', [], [rtl / 'wolf_pocket_loader.sv']),
        ('apf', 'tb_apf_ready_4k', [], [rtl / 'wolf_pocket_loader.sv', *common]),
        ('display', 'tb_display_integration', [], [
            rtl / 'core_top.sv', rtl / 'wolf_pocket_loader.sv', rtl / 'wolf_pocket_video.sv',
            rtl / 'wolf_pocket_loading.sv', rtl / 'wolf_pocket_audio.sv', *common,
            tests / 'display_integration_stubs.sv']),
        ('sameclock', 'tb_sameclock_perf', ['-DPOCKET', '-DSYNTHESIS'], [adapter]),
        ('request_qualifier', 'tb_request_qualifier', ['-DPOCKET', '-DSYNTHESIS'], [adapter]),
        ('tms_adapter', 'tb_tms_adapter_perf', ['-DPOCKET', '-DSYNTHESIS'], [
            *tms_sources, adapter, tests / 'sim_memory_model.sv']),
        ('ram_fields', 'tb_ram_write_perf', ['-DPOCKET', '-DSYNTHESIS'], [ram]),
        ('tms_ram', 'tb_tms_ram_perf', ['-DPOCKET', '-DSYNTHESIS'], [
            *tms_sources, adapter, ram, tests / 'sim_memory_model.sv',
            tests / 'tb_ram_write_perf.sv']),
        ('rom_cache', 'tb_rom_cache', ['--assert', '--x-initial', 'unique', '--x-assign', 'unique'], [
            sdram / 'yunit_sdram_arb.sv', tests / 'yunit_sdram_arb_baseline.sv']),
        ('gfx-stream-burst', 'tb_gfx_stream_burst', ['--assert'], [
            sdram / 'wolf_gfx_ddr_top.sv', sdram / 'stv_vram_ddr_agent.sv',
            sdram / 'wolf_ddr3_arb.sv']),
    ]
    if args.only:
        groups = {
            'performance': {'sameclock', 'request_qualifier', 'tms_adapter', 'ram_fields', 'tms_ram', 'rom_cache', 'gfx-stream-burst'},
            'ram': {'ram_fields', 'tms_ram'},
            'rom-cache': {'rom_cache'},
        }
        selected = groups.get(args.only, {args.only})
        cases = [case for case in cases if case[0] in selected]
    if args.full and args.only in (None, 'loader'):
        cases.append(('loader_full', 'tb_loader_4k', ['-DFULL_ASSETS'], [rtl / 'wolf_pocket_loader.sv']))
    build = ROOT / 'build/rtl-tests'
    build.mkdir(parents=True, exist_ok=True)
    (ROOT / 'build/loading-tests').mkdir(parents=True, exist_ok=True)
    results = []
    for name, top, defines, files in cases:
        sources = [*files, tests / (top + '.sv')]
        tracked = sources + ([rtl / 'openice_loading.hex'] if name in {'display', 'loading'} else [])
        source_hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                         for path in tracked}
        obj = build / ('obj-' + name)
        start = time.monotonic()
        command = [executable, '--binary', '--timing', '-Wno-fatal', '--top-module', top,
                   '--Mdir', str(obj), '-j', str(args.jobs), *defines, *map(str, sources)]
        with (build / (name + '-build.log')).open('w') as log:
            subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        run_args = ['+verilator+rand+reset+2', '+verilator+seed+1'] if name == 'rom_cache' else []
        run = subprocess.run([str(obj / ('V' + top)), *run_args], cwd=ROOT, capture_output=True,
                             text=True, timeout=180)
        (build / (name + '-run.log')).write_text(run.stdout + run.stderr)
        print(run.stdout + run.stderr, end='', flush=True)
        current_hashes = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                          for path in tracked}
        if current_hashes != source_hashes:
            raise RuntimeError('Source changed during test: ' + name)
        results.append({'test': name, 'exit': run.returncode,
                        'elapsed_seconds': round(time.monotonic() - start, 2),
                        'source_sha256': source_hashes})
        (build / 'results.json').write_text(json.dumps({'results': results}, indent=2) + '\n')
        run.check_returncode()
    if args.images:
        subprocess.run([sys.executable, str(tests / 'check_loading_pixels.py')], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
