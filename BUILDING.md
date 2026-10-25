# Building the Pocket core

Tag `v0.1.0-test.5` contains the preferred sources and exact Quartus project inputs for the test.5 FPGA image. This build adds the title/progress display and memory optimizations. The exact released image was tested on Pocket, with smoother gameplay and a working loading display reported on 25 October 2026. Game ROMs are loaded at runtime and are not needed for synthesis.

The compiled source and project hashes are recorded in `source-manifest.json`. Four-corner timing, memory-interface, clock-enable and clock-domain-crossing checks were reviewed before the Pocket trial. This community test does not establish exact arcade timing or exhaustive hardware validation. A new build needs its own review; an earlier result does not qualify a different image.

## Layout

- `src/`: preferred SystemVerilog/source inputs, including modified upstream files and the loading bitmap. Paths and contents are recorded in `source-manifest.json`.
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

Review the assembler, fitter and TimeQuest reports. A successful synthesis alone is insufficient. The test.5 fit used seed 3, four processors, 17,055 / 18,480 ALMs and 298 / 308 M10Ks. Four-corner setup slack was +0.071 / +0.146 / +3.602 / +3.937 ns (slow 85°C, slow 0°C, fast 85°C, fast 0°C); minimum hold slack was +0.119 ns. These values describe the released fit, not a guarantee for a new build or different constraints.

`quartus/core/core_constraints.sdc` is the **effective project SDC**. The copy in `src/pocket/core_constraints.sdc` is retained as an original source input. The test.5 fit has 17 physical DCS exec registers, independently checked against the effective constraint collections. The loading-display review found seven Gray-code progress source registers with no physical replicas and nine two-stage synchronizer chains. The SDC collections include any fitted source replicas when present. Each fresh fit needs renewed collection and physical checks; do not weaken assertions simply to obtain a passing report.

The APF pre-flow script regenerates a timestamp and random build identifier. Therefore a normal recompile is **not promised to produce a byte-identical bitstream**. The checked-in `build_id.mif` records the released build's ID. Changes to HDL, tools, seeds or timing constraints require new verification and hardware testing.

Quartus emits native `.rbf` data. Pocket uses `.rbf_r`, with the eight bits of every byte reversed (not the order of bytes). The test.5 native SHA-256 is `e51bd0939dfca9e4d4bc3dbd7ef5d8154a8475c1da5d0e86a8d6649ff6c8059e`; the distributed `.rbf_r` SHA-256 is `0917a47d7c275b6ca1f6cb0bf5e07fb4e4ed0e255645ecc32e3b9c91cef2c6a4` (2,142,972 bytes).

## Optional SystemVerilog conversion

The generated Verilog is included, so sv2v is not required for the compile above. To reproduce it from the preferred source form, use **sv2v 0.0.13**:

```sh
python3 tools/regenerate_verilog.py --sv2v /path/to/sv2v
```

The script uses the recorded source order and defines and checks the resulting SHA-256. The public generated Verilog is byte-identical to the input used for the test.5 compile. The released FPGA binary is the image tested on Pocket.

## Prepare a release

The packager requires a release-ready source manifest and checks the included bitstream hash. Before preparing a different release, update the binary, its corresponding source/project provenance and the validation record together.

```sh
python3 tools/check_release.py
python3 -m unittest discover -s tests -v
python3 tools/make_release.py
```

The packager reads an explicit list of files. It includes the bitstream, APF metadata, instructions, licenses and ROM preparation tool, but never the game assets. Its output is a single installable ZIP in `dist/`. Corresponding sources are available from the same release tag in this repository.

The unit tests use synthetic byte strings, not copyrighted game data. They verify rejected checksums and missing/duplicate inputs, ZIP handling and preservation of different existing output files. On the development machine, the preparation script was additionally checked against the supplied revision 1.21 ROMs; its three output hashes matched the assets used in the Pocket test. Existing prepared assets remain compatible with test.5.

The `0.1.0-test.4.1` packaging update adds the supplied cover and a Pocket platform image; its FPGA bitstream is identical to test.4. `Platforms/_images/openice.bin` is an APF menu bitmap, not a ROM. It is explicitly allowlisted by the packager. To rebuild that image only, install Pillow and run `python3 tools/build_platform_image.py`. This optional artwork dependency is not needed for preparing ROM assets, validating the core or creating a release from the checked-in files.

## Validation scope

The Pocket configuration changes these memory paths:

- Aligned 16-bit and 32-bit RAM stores skip the read-before-write step because they replace complete words. Partial fields retain read-modify-write, bounds checks and acknowledgment of physical writes.
- A synchronous, direct-mapped cache holds 64 16-bit program words. It fills from completed SDRAM reads and invalidates on loader writes; read/write collisions cannot produce a cache hit.
- Dense 8-bit graphics streams prefetch up to four 64-bit beats within an aligned 32-byte block. Ownership remains held through the final response, even if the source resumes earlier. CPU graphics reads, demand misses and download writes stay single-beat; other hosts retain the original default.
- One redundant CPU-memory cooldown interval is removed. CPU clock enables and video, memory and audio clock rates remain unchanged, as do DMA cadence and publication fences.

The loading screen shows the title image, a bar and a percentage derived from physically drained ROM chunks across all 21 MiB of assets. Progress is stable within each displayed frame; the switch to game video waits for vertical sync. A value of 100% describes asset transfer, not completion of the game's own startup checks.

The synthetic RTL regressions can be run with Verilator and a C++ compiler:

```sh
python3 tools/run_rtl_tests.py --full
```

This covers the loader with all 21 MiB, strict APF startup, loading raster and handoff, CPU memory transactions, aligned and partial RAM fields, program-cache coherence, graphics bursts and small programs on the real TMS core. It uses no game ROMs. Use `--only ram`, `--only rom-cache` or `--only gfx-stream-burst` for those targeted checks. Add `--images` with Pillow installed for an independent pixel and percentage-glyph check. Rebuild the loading bitmap with `python3 tools/build_loading_image.py --check`; its optional Pillow dependency is separate from the standard-library ROM tool.

Component tests show fewer memory transactions and shorter execution times for selected CPU and dense-graphics workloads. Separate development fixtures exercise the graphics path with the actual PSRAM controller RTL, a delayed pin model, scanout and sound-region traffic. Those fixtures check matching pixels and bytes; their timing gains are not measurements of a hockey match or promises of a particular frame rate. The tester reported smoother gameplay and a working loading screen with the qualified test.5 image. This qualitative observation is distinct from component timing measurements. Camera tracking has not been separately quantified against an original board.

The original development work included functional simulations, four-corner timing analysis and memory-interface review. Hardware gameplay and sound were reported by auricom79 for test.4 on 20 October 2026; smoother gameplay and the new loading display were confirmed for test.5 on 25 October. Those observations are distinct from automated tests. The memory timing review uses stated PCB flight/capacitance assumptions, and the official APF integration does not supply every receiver timing budget; no unmeasured electrical compliance is claimed. The public CI checks source identity and packaging tools; it does not emulate a complete match or run Quartus. The private development history, ROMs, VM, raw simulation dumps and machine-specific logs are not part of this repository.
