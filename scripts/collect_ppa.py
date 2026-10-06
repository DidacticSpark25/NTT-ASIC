"""
collect_ppa.py - gather Genus / Innovus / Tempus reports from build/<cfg>/ into a PPA table.

  results/ppa.csv   one row per configuration
  results/ppa.md    markdown table for the README
  results/ppa.png   area vs. latency trade-off plot (if matplotlib is installed)

Report formats drift between tool versions, so every parser is best-effort: a value
that cannot be found is left blank rather than guessed.

Derived metrics
  fmax       = 1 / (T_clk - WNS)                     (post-route WNS if available, else Genus)
  latency    = compute cycles / fmax                 (cycles from the analytical model, which
                                                     the RTL testbench checks exactly)
  throughput = 1 / latency                           (transforms per second, compute only)
  ATP        = area x latency                        (lower is better)
"""
import csv
import glob
import gzip
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "model"))
from ntt_model import SCHEMES, cycle_count  # noqa: E402

NUM = r"[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?"


def read(path):
    for p in (path, path + ".gz"):
        if os.path.exists(p):
            opener = gzip.open if p.endswith(".gz") else open
            with opener(p, "rt", errors="replace") as f:
                return f.read()
    return None


def first(pattern, text, cast=float, flags=re.M):
    if not text:
        return None
    m = re.search(pattern, text, flags)
    return cast(m.group(1)) if m else None


# ---------------------------------------------------------------- Genus
def genus_area(text):
    """Total cell area of ntt_top + split by block type from the hierarchical report."""
    if not text:
        return {}
    out = {}
    sp = r"[ \t]"                                   # never let a match run across lines
    row = re.compile(rf"^({sp}*)(\S+){sp}+(?:(\S+){sp}+)?(\d+){sp}+({NUM}){sp}+({NUM}){sp}+({NUM})", re.M)
    blocks = {"bank": 0.0, "butterfly": 0.0, "modmul": 0.0, "tw_rom": 0.0}
    for m in row.finditer(text):
        inst, module = m.group(2), (m.group(3) or "")
        cell_area = float(m.group(5))
        if inst == "ntt_top" and "total_area" not in out:
            out["cells"] = int(m.group(4))
            out["cell_area"] = cell_area
            out["total_area"] = float(m.group(7))
            continue
        for key in blocks:
            if module.startswith(f"ntt_{key}"):
                blocks[key] += cell_area
    if "cell_area" in out and any(blocks.values()):
        out["area_banks"] = blocks["bank"]
        out["area_butterflies"] = blocks["butterfly"]
        out["area_modmul"] = blocks["modmul"]
        out["area_twiddle_rom"] = blocks["tw_rom"]
        out["area_ctrl_xbar"] = out["cell_area"] - blocks["bank"] - blocks["butterfly"] - blocks["tw_rom"]
    return out


def genus_slack_ns(text):
    v = first(rf"Timing slack\s*:\s*({NUM})\s*ps", text)
    if v is not None:
        return v / 1000.0
    v = first(rf"Slack\s*:=\s*({NUM})", text)
    return v / 1000.0 if v is not None else None


def genus_power_mw(text):
    v = first(rf"^\s*Subtotal\s+{NUM}\s+{NUM}\s+{NUM}\s+({NUM})", text)       # Genus 19+ (W)
    if v is not None:
        return v * 1e3
    v = first(rf"^\s*ntt_top\s+\d+\s+{NUM}\s+{NUM}\s+({NUM})", text)          # legacy (nW)
    return v / 1e6 if v is not None else None


# ---------------------------------------------------------------- Innovus / Tempus
def innovus_wns_ns(text):
    return first(rf"WNS \(ns\):\|\s*({NUM})", text)


def innovus_density(text):
    return first(rf"Density:\s*({NUM})\s*%", text)


def innovus_power_mw(text):
    return first(rf"^\s*Total Power:\s*({NUM})", text)


def die_area_um2(text):
    m = re.search(rf"DIE_BOX\s*\{{?\s*({NUM})\s+({NUM})\s+({NUM})\s+({NUM})", text or "")
    if not m:
        return None
    x0, y0, x1, y1 = map(float, m.groups())
    return (x1 - x0) * (y1 - y0)


def congestion(text):
    out = {}
    if not text:
        return out
    hs = re.findall(rf"\[hotspot\]\s*\|\s*({NUM})[^|]*\|\s*({NUM})", text)
    if hs:
        out["hotspot_max"], out["hotspot_total"] = map(float, hs[-1])
    ov = re.search(rf"({NUM})%\s*H.*?({NUM})%\s*V", text)
    if ov:
        out["overflow_h_pct"], out["overflow_v_pct"] = map(float, ov.groups())
    return out


def tempus_slack_ns(text):
    return first(rf"Slack Time\s+({NUM})", text)


# ---------------------------------------------------------------- main
def collect():
    rows = []
    for d in sorted(glob.glob(os.path.join(ROOT, "build", "*_p[0-9]*"))):
        name = os.path.basename(d)
        m = re.match(r"(kyber|dilithium)_(barrett|montgomery)_p(\d+)$", name)
        if not m or not os.path.isdir(os.path.join(d, "syn")):
            continue
        scheme, red, p = m.group(1), m.group(2), int(m.group(3))
        clk = first(rf"set CLK_PERIOD\s+({NUM})", read(os.path.join(d, "ntt_top.sdc")))
        r = {"config": name, "scheme": scheme, "reduction": red, "P": p, "clk_ns": clk}
        r.update(genus_area(read(f"{d}/syn/rpt/area.rpt")))
        r["syn_slack_ns"] = genus_slack_ns(read(f"{d}/syn/rpt/timing.rpt"))
        r["syn_power_mw"] = genus_power_mw(read(f"{d}/syn/rpt/power.rpt"))
        if os.path.isdir(f"{d}/pnr"):
            r["pnr_wns_ns"] = innovus_wns_ns(read(f"{d}/pnr/rpt/signoff/postroute.summary"))
            r["pnr_density_pct"] = innovus_density(read(f"{d}/pnr/rpt/signoff/postroute.summary"))
            r["pnr_power_mw"] = innovus_power_mw(read(f"{d}/pnr/rpt/power.rpt"))
            r["die_area_um2"] = die_area_um2(read(f"{d}/pnr/rpt/die.rpt"))
            r.update(congestion(read(f"{d}/pnr/rpt/congestion_place.rpt")))
        if os.path.isdir(f"{d}/sta"):
            r["sta_setup_slack_ns"] = tempus_slack_ns(read(f"{d}/sta/rpt/setup.rpt"))

        cyc = cycle_count(SCHEMES[scheme], p)["compute"]
        r["compute_cycles"] = cyc
        slack = next((r.get(k) for k in ("sta_setup_slack_ns", "pnr_wns_ns", "syn_slack_ns")
                      if r.get(k) is not None), None)
        if clk and slack is not None:
            fmax = 1e3 / (clk - slack)                     # MHz
            r["fmax_mhz"] = round(fmax, 1)
            r["latency_us"] = round(cyc / fmax, 3)
            r["throughput_kntt_s"] = round(fmax * 1e3 / cyc, 1)
            area = r.get("die_area_um2") or r.get("cell_area")
            if area:
                r["atp_mm2_us"] = round(area * 1e-6 * r["latency_us"], 5)
        rows.append(r)
    return rows


def write(rows):
    out = os.path.join(ROOT, "results")
    os.makedirs(out, exist_ok=True)
    keys = []
    for r in rows:
        keys += [k for k in r if k not in keys]
    with open(os.path.join(out, "ppa.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        w.writerows(rows)

    cols = [("config", "Config"), ("cell_area", "Cell area (um^2)"), ("fmax_mhz", "fmax (MHz)"),
            ("compute_cycles", "Cycles/NTT"), ("latency_us", "Latency (us)"),
            ("throughput_kntt_s", "kNTT/s"), ("syn_power_mw", "Power (mW)"),
            ("atp_mm2_us", "ATP (mm^2*us)"), ("die_area_um2", "Die (um^2)"),
            ("hotspot_max", "Congestion hotspot")]
    cols = [c for c in cols if any(r.get(c[0]) is not None for r in rows)]
    lines = ["| " + " | ".join(h for _, h in cols) + " |", "|" + "---|" * len(cols)]
    for r in rows:
        cells = []
        for k, _ in cols:
            v = r.get(k)
            if v is None:
                cells.append("")
            elif isinstance(v, float):
                cells.append(f"{v:,.0f}" if abs(v) >= 1000 else f"{v:.3g}")
            else:
                cells.append(str(v))
        lines.append("| " + " | ".join(cells) + " |")
    with open(os.path.join(out, "ppa.md"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        return
    pts = [r for r in rows if r.get("latency_us") and (r.get("die_area_um2") or r.get("cell_area"))]
    if not pts:
        return
    fig, ax = plt.subplots(figsize=(7, 4.5))
    marker = {"barrett": "o", "montgomery": "s"}
    color = {"kyber": "#2a6fdb", "dilithium": "#d9822b"}
    for r in pts:
        area = (r.get("die_area_um2") or r["cell_area"]) / 1e6
        ax.scatter(r["latency_us"], area, marker=marker[r["reduction"]], color=color[r["scheme"]], s=60)
        ax.annotate(f"P{r['P']}", (r["latency_us"], area), textcoords="offset points", xytext=(6, 4), fontsize=8)
    for s, c in color.items():
        ax.scatter([], [], color=c, label=s)
    for red, mk in marker.items():
        ax.scatter([], [], marker=mk, color="gray", label=red)
    ax.set_xlabel("NTT latency (us, compute only)")
    ax.set_ylabel("area (mm$^2$)")
    ax.set_title("NTT accelerator design space, gpdk045")
    ax.grid(alpha=0.3)
    ax.legend(frameon=False, fontsize=8)
    fig.tight_layout()
    fig.savefig(os.path.join(out, "ppa.png"), dpi=160)


if __name__ == "__main__":
    rows = collect()
    if not rows:
        print("no build/<cfg>/syn directories found - run `make syn` or `make sweep` first")
        sys.exit(0)
    write(rows)
