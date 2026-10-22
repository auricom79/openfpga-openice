# WOLF UNIT

### One core. Seven cabinets. Zero sleep cycles.

Attention, cathode-ray casuals and dial-up remnants. Power down your expectations and behold: the Midway **Wolf unit**, rebuilt in logic, not in emulation. No interpreter. No approximation. No "close enough." Gates. Wires. Silicon obeying orders.

You think you remember these machines? Cute. I was arbitrating their bus cycles while you were still learning that the quarter goes in the slot.

---

## 🔮 THE MANIFEST

One RBF. Seven titles. The MRA whispers a profile byte at index 3 and the fabric **becomes** the machine you asked for.

| profile | cabinet | romset |
|:---:|---|---|
| `00` | NHL Open Ice — 2 on 2 Challenge | `openice.zip` |
| `01` | WWF WrestleMania | `wwfmania.zip` |
| `02` | Mortal Kombat 3 | `mk3.zip` |
| `03` | Ultimate Mortal Kombat 3 | `umk3.zip` |
| `04` | NBA Hangtime | `nbahangt.zip` |
| `05` | NBA Maximum Hangtime | `nbamht.zip` |
| `06` | Rampage World Tour | `rmpgwt.zip` |

Rampage gets its own clock cadence because Rampage **demanded** it. The others fell in line.

---

## ❄️ THE BLACK ICE — SLAIN, WITNESSED, CLOSED

For as long as anyone has tried, NHL Open Ice on FPGA has drawn a rink of **absolute void**. Players skated on nothing. The puck crossed an abyss. Every build. Every attempt. Black ice.

Not anymore. And here is the corpse, laid out for inspection:

> The blitter's 8-bit-per-pixel source look-ahead was carrying a fetch address **across a row boundary**. The hardware reloads that pointer from the row base on **every single row**. How far the previous row actually *drew* is irrelevant to where the next one *reads*.
>
> It only bites when a row ends **early**. The rink is **860 wide with an endskip of 460** — so 400 of 860 pixels draw, and the carried address landed **460 pixels short**. Every row after the first read the wrong source data.
>
> And it was rink-*only* because that look-ahead is gated on `bpp==8`, and **the rink is the only 8-bpp blit in the entire game.** One object class dies. Everything else renders flawlessly. That is why it hid for so long.

Diagnosed from the game's own DMA register writes. Isolated by controls that proved it needed `bpp==8` **and** `endskip≠0` *together* — same geometry at 4bpp draws perfectly. Root-caused by experiment **before** a single line of fix was written.

**Confirmed on a real cabinet. The ice draws.** 🧊

---

## ⚡ WHAT THE ORACLES SAY

I do not ask you to trust me. I ask you to read the numbers.

- **203/203** blitter cases cross-diffed against an independent model — including **50 real captured UMK3 blits**
- **94.3%** of real blit volume now covered, up from 8.2% — because I stopped inventing test cases and started harvesting them from what the ROMs *actually issue*
- **87 distinct blitter regimes** measured across all seven titles. The old test matrix covered **six** of them. Six. The bug was never bad luck; it was a map drawn from imagination.
- Timing closed at **all four PVT corners, first fit.** No constraint relaxed. No corner dispositioned. No exceptions bolted on to make a number turn green.

---

## 📉 WHAT I WILL NOT PRETEND

A technomancer who lies about his own work is just a marketer with better lighting.

- The **DCS startup de-click** fix is real and measured against genuine firmware — but it is **not gated**, and its signature is a *click* while the reported artifact is a *blip*. It may not be the thing you hear.
- The cross-diff is a **dual transcription**. It catches independent errors. It **cannot** catch a shared misreading of the reference — and neither can mutation testing. Stated, not buried.
- Six of the seven titles carry the shared-core change but have **not** been cabinet-tested at this baseline.

If it breaks, tell me. Reality outranks my opinion of my own code.

---

## 🛠️ INSTALLATION RITUAL

1. `Arcade-WolfUnit.rbf` → wherever your arcade cores live
2. `*.mra` → your `_Arcade` folder
3. Supply your own legally-owned romsets

**No ROM data lives here.** None. Not one byte. Bring your own.

---

## 🙏 STANDING ON OTHERS' SHOULDERS

I am loud, not dishonest. This core contains work by people who are owed credit:

- **JT51** (YM2151) — *Jose Tejada (jotego)* — **GPL-3.0**
- **VHDL Joust2 / Williams sound + speech board** — *Dar — darfpga@aol.fr*
- **TMS34010 GSP core** — *Kevin Coleman* — MIT
- **MiSTer framework** — *MiSTer-devel contributors*
- **MAME** — *the MAME development team.* The behavioural reference this core was
  diffed against, line by line. Every register, every edge case, every "why does it
  do *that*" was answered by someone else's decades of patient, unglamorous
  reverse-engineering. The black ice above was found by reading their source and
  measuring against their emulation. Without MAME this core is guesswork with a
  soldering iron. **Thank you.**

Their licence files are preserved in place, in their own directories.

Because JT51 is GPL-3, **this combined work is GPL-3.** Stated plainly, up front, not buried in a footnote.

---

*The rink draws. The cabinets live. The matrix bends.*

**Adios, turd nuggets. Verrrrrmmpt.** 🤖⚡
