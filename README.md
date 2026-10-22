# NHL Open Ice for Analogue Pocket

An experimental openFPGA port of **NHL Open Ice: 2 on 2 Challenge**, revision **1.21**, for Analogue Pocket. Based on [blahm1d/wolf-unit](https://github.com/blahm1d/wolf-unit), with Pocket-specific memory, loading, video, audio and controller integration.

[Instructions en français](README.fr.md)

The `0.1.0-test.4` FPGA bitstream has been tested on a physical Pocket: the game boots, accepts credits, plays and produces sound. This is a community test release, not a claim of complete arcade accuracy or exhaustive validation. No game ROMs are included in this repository or its releases.

## Install

1. Download **`auricom79.OpenIce_0.1.0-test.4.zip`** from [Releases](https://github.com/auricom79/openfpga-openice/releases). The automatically generated GitHub source archives are for development.
2. Extract the release ZIP into the root of the Pocket microSD card, merging `Cores`, `Platforms` and `Assets`. The core folder is `Cores/auricom79.OpenIce`.
3. Supply your own **Open Ice revision 1.21** ROM set, either `openice.zip` or an extracted directory. Prepare the assets with Python 3.9 or newer. No extra Python packages are needed.

   From a source checkout:

   ```sh
   python3 tools/prepare_roms.py /path/to/openice.zip --output /path/to/SD/Assets/openice/common
   ```

   The release ZIP also includes the tool. For a macOS SD card mounted as `BOOT`:

   ```sh
   python3 /Volumes/BOOT/Cores/auricom79.OpenIce/tools/prepare_roms.py ~/Downloads/openice.zip --output /Volumes/BOOT/Assets/openice/common
   ```

   Windows example:

   ```powershell
   py -3 E:\Cores\auricom79.OpenIce\tools\prepare_roms.py C:\ROMs\openice.zip --output E:\Assets\openice\common
   ```

   Replace the paths or drive letter with your own. The script checks all 22 ROM files by size, CRC32 and SHA-1, then checks the SHA-256 of each prepared stream. It does not download ROMs or modify the originals. A different revision will be rejected. It refuses to overwrite different existing assets.

4. The asset directory must contain:

   | File | Bytes |
   | --- | ---: |
   | `openice-program.bin` | 1,048,576 |
   | `openice-graphics.bin` | 16,777,216 |
   | `openice-sound.bin` | 4,194,304 |

5. Safely eject the card, insert it in the Pocket and select **openFPGA → NHL Open Ice**.

**Loading takes several minutes in this release.** A striped screen can remain visible while the assets load. During initial testing, allow five minutes without opening the menu before diagnosing a failure; this is a troubleshooting interval, not a measured startup guarantee.

## Start playing

On a fresh boot, `CMOS INVALID — FACTORY SETTINGS RESTORED` may appear because persistent CMOS saving is not implemented. Press a game button to continue.

The factory settings require **two credits to start**. Press **Select** several times, releasing it between presses, then press **Start**. Four separated Select presses followed by Start worked in hardware testing. Use **B** to confirm menu choices, including the initials prompt.

| Pocket control | Game action |
| --- | --- |
| D-pad | Move / select |
| A | Turbo |
| B | Shoot / block; confirm menus |
| X | Pass / steal |
| Select | Insert coin |
| Start | Start / join |

If an apparent stuck screen persists, try a complete Pocket power-off and restart, then allow loading to finish. An earlier report of a fixed statistics screen was resolved by that sequence; its exact cause was not established.

## Status and limitations

- Gameplay and audible sound were confirmed by the tester on 20 October 2026. An initial possible slowdown report was subsequently withdrawn; performance against an original arcade board has not been measured.
- Loading is slow and has no progress display yet.
- CMOS settings and records are not saved between sessions. Save states and sleep are not supported.
- Dock capability is declared in the APF metadata and two controllers are mapped, but Dock, multiplayer and analog output have not been validated; analog output is disabled.
- Only revision 1.21 is supported by the asset preparation tool. Other Wolf Unit games are not supported by this release.
- Full-match completion, extended stability and arcade timing fidelity are not yet independently verified.

Report reproducible problems through [Issues](https://github.com/auricom79/openfpga-openice/issues), including core version, Pocket firmware, boot or gameplay stage, controls used and whether sound is affected. Do not attach game ROMs.

## Development and credits

See [BUILDING.md](BUILDING.md) for the corresponding source snapshot and Quartus build instructions. The released bitstream is unchanged from the working local test.4; only public packaging and identifying metadata were adjusted.

- **blahm1d and Wolf Unit contributors** — original [Wolf Unit FPGA implementation](https://github.com/blahm1d/wolf-unit).
- **Kevin Coleman** — TMS34010 core.
- **Sorgelig and MiSTer contributors** — reused SDRAM and framework work.
- **Adam Gastineau (agg23)** — Analogue Pocket utilities.
- **Analogue** — openFPGA framework and core template.
- **MAME developers** — hardware reference and ROM identification metadata.
- **auricom79** — Pocket port project and hardware testing, developed with assistance from OpenAI Codex.

The combined project follows the upstream GPL-3.0 declaration; individual MIT, APF and Intel notices remain in place. See [NOTICE.txt](NOTICE.txt), [LICENSE](LICENSE), and `licenses/`. This is an unofficial community project, not affiliated with Analogue, Midway or the NHL. Supply your own game data; no ROM download service is provided.
