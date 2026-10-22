# Building the Pocket core

This repository publishes the source snapshot corresponding to the hardware-tested `0.1.0-test.4` bitstream. Game ROMs are loaded at runtime and are not needed for synthesis.

## Layout

- `src/`: 60 original SystemVerilog/source inputs from the tested build, including modified upstream files. Paths and contents are recorded in `source-manifest.json`.
- `quartus/`: self-contained Pocket project, combined generated Verilog, APF framework, pin assignments, PLL and effective timing constraints.
- `pocket/`: ROM-free deployment files and the tested bitstream.
- `tools/`: source/release checks, asset preparation, optional HDL regeneration and release packaging.
- `licenses/`: preserved notices and license texts.

## Compile

Use **Quartus Prime Lite 18.1.0 Build 625**, with **Cyclone V** device support. The target is `5CEBA4F23C8`. Compilation was performed under Linux; the original development host was an Apple Silicon Mac using a local Linux environment with x86 compatibility. That VM and the proprietary Quartus tools are not distributed here.

From a fresh checkout, with Quartus on `PATH`:

```sh
python3 tools/check_release.py
python3 -m unittest discover -s tests -v
mkdir -p build
cp -R quartus build/quartus
cd build/quartus
quartus_sh --64bit --flow compile ap_core
```

Review the assembler, fitter and TimeQuest reports. A successful synthesis alone is insufficient. The reference fit used seed 2, four processors, 16,729 / 18,480 ALMs and 279 / 308 M10Ks. Four-corner setup slack was +0.084 / +0.409 / +3.401 / +3.739 ns; minimum hold slack was +0.062 ns. These values describe the released fit, not a guarantee for a new build or different constraints.

`quartus/core/core_constraints.sdc` is the **effective final SDC**. The copy in `src/pocket/core_constraints.sdc` is retained as an original source input. The final SDC corrects a fitted DCS endpoint-count assertion from 16 to 17 physical registers; it does not change timing exceptions. The first flow stopped at that assertion, after which TimeQuest was rerun successfully with the independently checked count. A fresh fit may require renewed collection and physical checks; do not weaken assertions simply to obtain a passing report.

The APF pre-flow script regenerates a timestamp and random build identifier. Therefore a normal recompile is **not promised to produce a byte-identical bitstream**. The checked-in `build_id.mif` records the released build's ID. Changes to HDL, tools, seeds or timing constraints require new verification and hardware testing.

Quartus emits native `.rbf` data. Pocket uses `.rbf_r`, with the eight bits of every byte reversed (not the order of bytes). The reference native SHA-256 is `ce56186f9e79757a7b350e4ee14cd7dca5b89063c55ca68976d8953490b0b648`; the distributed `.rbf_r` SHA-256 is `f3c14c479397e1fab167ff227eeb5145d04a61de75c343534959e8820ff21971`.

## Optional SystemVerilog conversion

The generated Verilog is included, so sv2v is not required for the compile above. To reproduce it from the preferred source form, use **sv2v 0.0.13**:

```sh
python3 tools/regenerate_verilog.py --sv2v /path/to/sv2v
```

The script uses the recorded source order and defines and checks the resulting SHA-256. Three machine-specific paths in generated `$display` diagnostics were normalized to `src/` for publication. No HDL expressions were changed. Original and public generated-file hashes are recorded in `source-manifest.json`. The released FPGA binary is unchanged.

## Prepare a release

```sh
python3 tools/check_release.py
python3 -m unittest discover -s tests -v
python3 tools/make_release.py
```

The packager reads an explicit list of files. It includes the bitstream, APF metadata, instructions, licenses and ROM preparation tool, but never the game assets. Its output is a single installable ZIP in `dist/`. Corresponding sources are available from the same release tag in this repository.

The unit tests use synthetic byte strings, not copyrighted game data. They verify rejected checksums and missing/duplicate inputs, ZIP handling and preservation of different existing output files. On the development machine, the preparation script was additionally checked against the supplied revision 1.21 ROMs; its three output hashes matched the assets used in the Pocket test.

## Validation scope

The original development work included functional simulations, four-corner timing analysis and memory-interface review. Hardware gameplay and sound were reported by auricom79 on 20 October 2026. Those observations are distinct from automated tests. The public CI checks source identity and packaging tools; it does not emulate a complete match or run Quartus. The private development history, ROMs, VM, raw simulation dumps and machine-specific logs are not part of this repository.
