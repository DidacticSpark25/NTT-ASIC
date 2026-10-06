"""
gen_vectors.py - test vectors for the RTL testbenches.

  <out>_in.hex    NTEST x 256 input coefficients (edge cases first, then random)
  <out>_ntt.hex   expected forward NTT  (bit-reversed order, [0,q))
  <out>_intt.hex  expected inverse NTT of the *input* (inputs read as NTT-domain vectors)

Expected values come from the algorithmic model, which test_model.py checks against the
pq-crystals reference C code. Outputs are identical for Barrett and Montgomery builds
and for every lane count, so one vector set per scheme covers all configurations.

usage: python3 model/gen_vectors.py --scheme kyber --n 32 --out build/vec/kyber
"""
import argparse
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
from ntt_model import SCHEMES, ntt, intt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scheme", choices=SCHEMES, required=True)
    ap.add_argument("--n", type=int, default=32)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    s = SCHEMES[a.scheme]
    q = s.q
    rng = random.Random(a.seed)
    edge = [[0] * 256, [q - 1] * 256, [1] + [0] * 255, [0] * 255 + [q - 1],
            [i % q for i in range(256)], [(q - 1) if i & 1 else 0 for i in range(256)]]
    polys = edge[: a.n]
    while len(polys) < a.n:
        polys.append([rng.randrange(q) for _ in range(256)])

    digits = (s.w + 3) // 4
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    for suffix, fn in (("in", lambda p: p), ("ntt", lambda p: ntt(p, s)), ("intt", lambda p: intt(p, s))):
        with open(f"{a.out}_{suffix}.hex", "w") as f:
            for p in polys:
                for v in fn(p):
                    f.write(f"{v:0{digits}x}\n")
    print(f"{a.scheme}: {a.n} polynomials -> {a.out}_{{in,ntt,intt}}.hex")


if __name__ == "__main__":
    main()
