# One-week plan (Tue 6 Oct to Mon 12 Oct 2026)

Already done: golden model, RTL, open-source verification (947k checks), Cadence scripts.
What remains needs lab time on the Cadence tools.

| Day | Goal | Commands | Done when |
|---|---|---|---|
| **Tue 6** | Repo on GitHub; lab setup | `git push`; on the lab machine: `git clone`, `cp flow/config.example.tcl flow/config.tcl`, `flow/find_pdk.sh <gpdk045>` | `make check-config` passes |
| **Wed 7** | Xcelium regression and coverage. First synthesis | `make xrun-all`; `make syn SCHEME=kyber RED=barrett P=2 CLK=3.0` | All 12 PASS, coverage report saved; Genus netlist written |
| | Find fmax | rerun `make syn` with CLK = 2.5, 2.0, ... | Slack about 0 at the chosen CLK (Kyber and Dilithium may differ) |
| **Thu 8** | Equivalence, GLS, synthesis sweep | `make lec`; `make gls`; `make sweep` | 0 non-equivalent points; GLS PASS; `results/ppa.md` has 12 rows |
| **Fri 9** | First GDSII | `make pnr` and `make sta` for kyber_barrett_p2 | `ntt_top.gds` exists, WNS >= 0, `verify_drc` clean |
| **Sat 10** | Congestion study | `PNR=1 SCHEMES=kyber make sweep` (P = 1, 2, 4, both reductions) | Hotspot / overflow numbers for every P |
| **Sun 11** | Sign-off extras | `make power` (try `RUN_RAIL=1`), `make gls-sdf`, `make drc lvs` | Power numbers; post-route GLS PASS; DRC/LVS reports |
| **Mon 12** | Write-up | `make ppa`; Innovus screenshots in `docs/img/`; fill the README results table; push | README tells the full story with numbers |

## Fixing timing in Genus or Innovus

1. Open `build/<cfg>/syn/rpt/timing.rpt`. The worst path is almost always one of two:
   * the Barrett quotient multiply (stage 2 of `ntt_modmul`; Dilithium's is 46x24 bits),
   * the address-generation to twiddle-ROM path.
2. For the multiplier, add a pipeline stage. This also changes `BF_LAT` in
   `ntt_core.v`, `bf_latency` in `model/ntt_model.py`, and `EXP_COMP` in the testbench.
   Run `make regress` afterwards.
3. Or relax `CLK`. Report both numbers; the comparison is the point of the study.

## Resume bullets (fill the brackets after the lab runs)

**Post-Quantum NTT Accelerator ASIC (Kyber / Dilithium)** | Verilog HDL, Cadence Xcelium/Genus/Conformal/Innovus/Tempus, GPDK045, Python

* Designed a parameterized NTT/INTT accelerator for ML-KEM and ML-DSA with 1/2/4 pipelined
  CT/GS butterflies over a conflict-free XOR-banked memory; folded `n^-1` scaling into the
  inverse butterflies (no extra pass).
* Compared Barrett vs. Montgomery modular reduction. Verified RTL bit-exact against a Python
  golden model cross-checked with the pq-crystals reference C: 947K checks over 12
  configurations, plus exhaustive 11M-product reducer proofs.
* Took the design RTL-to-GDSII on 45 nm: [X] MHz, [Y] mm^2, [Z] us per Kyber NTT. Found that
  [Montgomery / Barrett] saves [N]% area, and that P=4 raises routing hotspots by [M]x vs. P=1.
