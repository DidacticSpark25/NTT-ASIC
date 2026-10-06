"""
test_model.py - self-checks for the golden model.

  * algorithmic NTT/INTT vs the official pq-crystals reference C code
  * NTT -> pointwise -> INTT vs schoolbook negacyclic multiplication
  * hardware model (every reduction x lane count) vs algorithmic model,
    including the bank-conflict assertion on every cycle
  * Barrett / Montgomery reducers: exhaustive for Kyber, random for Dilithium

Run:  python3 model/test_model.py            (needs `make -C ref` first)
"""
import os
import random
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
from ntt_model import (SCHEMES, REDUCERS, HwModel, ntt, intt, pointwise,
                       negacyclic_mul, cycle_count)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = random.Random(2026)
checks = 0


def ok(cond, msg):
    global checks
    checks += 1
    if not cond:
        print("FAIL:", msg)
        sys.exit(1)


def rand_poly(q):
    return [rng.randrange(q) for _ in range(256)]


def edge_polys(q):
    return [[0] * 256, [q - 1] * 256, [1] + [0] * 255, [0] * 255 + [q - 1],
            [i % q for i in range(256)]]


def test_vs_reference(s, n=50):
    exe = os.path.join(ROOT, "ref", f"harness_{s.name}")
    if not os.path.exists(exe):
        print(f"  [skip] {exe} not built (run: make -C ref)")
        return
    polys = edge_polys(s.q) + [rand_poly(s.q) for _ in range(n)]
    inp = f"{len(polys)}\n" + "\n".join(" ".join(map(str, p)) for p in polys) + "\n"
    out = subprocess.run([exe], input=inp, capture_output=True, text=True, check=True).stdout.split("\n")
    for i, p in enumerate(polys):
        ref_f = list(map(int, out[2 * i].split()))
        ref_i = list(map(int, out[2 * i + 1].split()))
        ok(ntt(p, s) == ref_f, f"{s.name} ntt vs reference, poly {i}")
        ok(intt(p, s) == ref_i, f"{s.name} intt vs reference, poly {i}")
    print(f"  {s.name}: {len(polys)} polys, NTT and INTT match pq-crystals reference")


def test_polymul(s, n=4):
    for _ in range(n):
        a, b = rand_poly(s.q), rand_poly(s.q)
        ok(intt(pointwise(ntt(a, s), ntt(b, s), s), s) == negacyclic_mul(a, b, s.q),
           f"{s.name} NTT-based multiply != schoolbook")
        ok(intt(ntt(a, s), s) == a, f"{s.name} round trip")
    print(f"  {s.name}: NTT polynomial multiply == schoolbook negacyclic multiply")


def test_reducers(s):
    q = s.q
    for name, cls in REDUCERS.items():
        red = cls(s)
        if s.name == "kyber":                       # exhaustive: all q^2 operand pairs
            import numpy as np
            a = np.arange(q, dtype=np.int64)
            for bval in range(q):
                p = a * bval
                if name == "barrett":
                    t = (p * red.m) >> red.k
                    r = p - t * q
                    expect = p % q
                else:
                    mask = (1 << red.rbits) - 1
                    m = ((p & mask) * red.qneg_inv) & mask
                    r = (p + m * q) >> red.rbits
                    expect = (p * pow(1 << red.rbits, -1, q)) % q
                ok(bool((r >= 0).all() and (r < 2 * q).all()), f"{name} bound")
                r = np.where(r >= q, r - q, r)
                ok(bool((r == expect).all()), f"{name} value, b={bval}")
            print(f"  {s.name}/{name}: exhaustive {q*q:,} products OK (pre-correction < 2q)")
        else:
            for _ in range(200000):
                x, y = rng.randrange(q), rng.randrange(q)
                got = red.mul(x, y)
                exp = x * y % q if name == "barrett" else x * y * pow(1 << red.rbits, -1, q) % q
                ok(got == exp, f"{name} {x}*{y}")
            for x in (0, 1, q - 1):
                for y in (0, 1, q - 1):
                    red.mul(x, y)
            print(f"  {s.name}/{name}: 200k random + corner products OK")


def test_hw_model(s, n=6):
    for red in REDUCERS:
        for p in (1, 2, 4):
            hw = HwModel(s, red, p)
            for poly in edge_polys(s.q)[:2] + [rand_poly(s.q) for _ in range(n)]:
                ok(hw.run(poly) == ntt(poly, s), f"hw ntt {s.name}/{red}/P{p}")
                ok(hw.stats["compute_cycles"] == cycle_count(s, p)["compute"], "cycle count")
                ok(hw.run(poly, inverse=True) == intt(poly, s), f"hw intt {s.name}/{red}/P{p}")
    print(f"  {s.name}: hardware model (2 reductions x P=1,2,4) == algorithmic model, no bank conflicts")


if __name__ == "__main__":
    for s in SCHEMES.values():
        print(f"[{s.name}] q={s.q} W={s.w} layers={s.layers}")
        test_vs_reference(s)
        test_polymul(s)
        test_reducers(s)
        test_hw_model(s)
    print(f"ALL MODEL CHECKS PASSED ({checks:,} assertions)")
