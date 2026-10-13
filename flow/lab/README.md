# Lab flow (as actually run)

These are the scripts that produced the results in the main README. They are a
condensed version of `flow/genus/` and `flow/innovus/` that runs without the
Makefile or `flow/config.tcl`, which is easier on a shared lab server.

| Step | Command (from the repo root) | Time on the lab server |
|---|---|---|
| RTL simulation | `xrun -access +rwc -incdir rtl rtl/ntt_bank.v rtl/ntt_tw_rom.v rtl/ntt_modmul.v rtl/ntt_butterfly.v rtl/ntt_core.v tb/tb_ntt_core.v +vec=tb/vectors/kyber` | ~1 min |
| Waveforms | same + `-defparam tb_ntt_core.NTEST=1 -gui` | — |
| Synthesis | `genus -files flow/lab/genus_lab.tcl` | ~5 min |
| Place and route to GDSII | `cd pnr && innovus -files ../flow/lab/innovus_lab.tcl` | ~20 min |

Edit `LIBS` at the top of both Tcl files to point at the 45 nm library folder
(the one containing `lib/max/slow.lib`, `lib/min/fast.lib` and `lef/gsclib045.fixed.lef`).

## Problems hit on the way (and the fixes, all in the repo now)

| Symptom | Cause | Fix |
|---|---|---|
| xrun: `*E,PTSNUM ... -timescale` | lab xrun setup rejected the option | removed; every source file declares its own `` `timescale `` |
| xrun: `cannot open include file ntt_defs.vh` | headers passed as sources / no include dir | compile only the 6 `.v` files, add `-incdir rtl` |
| Genus: 0 cells, `u_core` black box | Genus parses `.v` as strict Verilog-2001; `localparam` inside `generate` is 2005 | RTL made 2001-clean; read with `read_hdl -sv` |
| Genus: area 0.000 | the training `slow.lib` carries no cell areas | area taken from Innovus (LEF sizes) |
| Innovus: `Failed to open file mmmc.tcl` | relative paths, Innovus started in another folder | absolute paths |
| Innovus: `IMPOPT-7027` at `timeDesign -postRoute` | post-route analysis needs OCV mode | `setAnalysisMode -analysisType onChipVariation -cppr both` |
