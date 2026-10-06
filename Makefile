# ============================================================================
# NTT accelerator for post-quantum cryptography - RTL to GDSII on gpdk045
#
# Configuration (any target):
#   SCHEME = kyber | dilithium        RED = barrett | montgomery
#   P      = 1 | 2 | 4  (butterflies) CLK = clock period in ns   UTIL = core utilization
#
# Open-source (runs anywhere, also in CI):
#   make model        golden model self-test vs pq-crystals reference C
#   make regress      RTL regression, all 12 configs (Icarus Verilog)
#   make gls-yosys    gate-level sim of a Yosys netlist (synth/sim mismatch check)
#
# Cadence flow (lab machines; needs flow/config.tcl):
#   make xrun         Xcelium simulation + coverage for one config (make xrun-all: all 12)
#   make syn          Genus synthesis
#   make lec          Conformal equivalence RTL vs netlist
#   make gls          Xcelium gate-level sim of the synthesized netlist
#   make pnr          Innovus place & route -> GDSII
#   make gls-sdf      Xcelium post-route gate-level sim with SDF
#   make sta          Tempus sign-off timing
#   make power        Voltus power (RUN_RAIL=1 for IR drop)
#   make drc / lvs    Pegasus deck-based checks (templates)
#   make flow         syn -> lec -> pnr -> sta -> power for one config
#   make sweep        synthesis (and PNR=1: place & route) for all configs, then PPA table
#   make ppa          collect reports into results/ppa.{csv,md,png}
# ============================================================================
SCHEME ?= kyber
RED    ?= barrett
P      ?= 2
CLK    ?= 3.0
UTIL   ?= 0.60

REPO   := $(abspath .)
CFG    := $(SCHEME)_$(RED)_p$(P)
BUILD  := $(REPO)/build/$(CFG)
SI     := $(if $(filter kyber,$(SCHEME)),0,1)
RI     := $(if $(filter barrett,$(RED)),0,1)
export REPO BUILD UTIL

GENUS   ?= genus
INNOVUS ?= innovus
TEMPUS  ?= tempus
VOLTUS  ?= voltus

.PHONY: help model rtl regress gls-yosys cfg xrun xrun-all syn lec gls pnr gls-sdf sta power drc lvs flow sweep ppa clean check-config

help:
	@sed -n '2,30p' Makefile

# ---------------- open-source ----------------
model:
	$(MAKE) -C ref
	python3 model/test_model.py

rtl:
	python3 model/gen_rtl.py

regress: rtl
	scripts/regress.sh $(or $(NTEST),16)

gls-yosys: rtl
	scripts/gls_yosys.sh $(SCHEME) $(RED) $(P)

# ---------------- per-config setup ----------------
# regenerated on every run so a changed CLK or P can never use stale files
cfg:
	@mkdir -p $(BUILD)
	@printf '`define NTT_SCHEME %s\n`define NTT_RED %s\n`define NTT_P %s\n' $(SI) $(RI) $(P) > $(BUILD)/ntt_cfg.vh
	@sed 's/@CLK_PERIOD@/$(CLK)/' flow/constraints/ntt_top.sdc.in > $(BUILD)/ntt_top.sdc
	@echo "config $(CFG): SCHEME=$(SI) RED=$(RI) P=$(P) CLK=$(CLK)ns"

check-config:
	@test -f flow/config.tcl || (echo "ERROR: cp flow/config.example.tcl flow/config.tcl and edit the PDK paths"; exit 1)

# ---------------- Cadence ----------------
xrun: rtl
	flow/xcelium/run_xrun.sh $(SCHEME) $(RED) $(P) $(or $(NTEST),16)

xrun-all: rtl
	flow/xcelium/run_xrun.sh all $(or $(NTEST),16)

syn: check-config rtl cfg
	@mkdir -p $(BUILD)/syn
	cd $(BUILD)/syn && $(GENUS) -batch -files $(REPO)/flow/genus/syn.tcl -log genus

lec: check-config
	flow/conformal/run_lec.sh $(BUILD)

gls: check-config
	flow/xcelium/run_gls.sh $(BUILD) syn

pnr: check-config
	@mkdir -p $(BUILD)/pnr
	cd $(BUILD)/pnr && $(INNOVUS) -no_gui -init $(REPO)/flow/innovus/pnr.tcl -log innovus.log

gls-sdf: check-config
	flow/xcelium/run_gls.sh $(BUILD) pnr

sta: check-config
	@mkdir -p $(BUILD)/sta
	cd $(BUILD)/sta && $(TEMPUS) -no_gui -files $(REPO)/flow/tempus/sta.tcl -log tempus.log

power: check-config
	@mkdir -p $(BUILD)/power
	cd $(BUILD)/power && $(VOLTUS) -no_gui -files $(REPO)/flow/voltus/power.tcl -log voltus.log

drc: check-config
	flow/pv/run_pegasus.sh $(BUILD) drc

lvs: check-config
	flow/pv/run_pegasus.sh $(BUILD) lvs

flow: syn lec pnr sta power
	@echo "GDSII: $(BUILD)/pnr/out/ntt_top.gds"

sweep: check-config rtl
	scripts/sweep.sh

ppa:
	python3 scripts/collect_ppa.py

clean:
	rm -rf build ref/harness_kyber ref/harness_dilithium
