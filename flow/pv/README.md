# Physical verification (DRC / LVS)

Innovus runs `verify_drc`, `verifyConnectivity` and `verifyProcessAntenna` at the end of
`flow/innovus/pnr.tcl`; those reports land in `build/<cfg>/pnr/rpt/`. They are the
baseline sign-off and need no extra licence.

For deck-based sign-off, use whatever your lab licenses. GPDK045 ships PVS/Pegasus decks
(`pvlDRC.rul`, `pvlLVS.rul`); many labs also have Calibre decks. Paths go in
`flow/config.tcl` (`PVS_DRC_RULES`, `PVS_LVS_RULES`, `STD_CDL`).

`run_pegasus.sh` is a starting point. Rule-deck switches and the LVS source netlist
format differ between PDK releases, so check the deck header before the first run.

```
flow/pv/run_pegasus.sh build/kyber_barrett_p2 drc
flow/pv/run_pegasus.sh build/kyber_barrett_p2 lvs
```

LVS source netlist: Innovus writes `pnr/out/ntt_top.lvs.v` (with power/ground). Convert it
to SPICE with `v2lvs` (Calibre) or let Pegasus read Verilog directly with the std-cell CDL.
