"""
ntt_model.py - Golden model for the NTT/INTT accelerator.

Three layers of model, each checked against the one above it:

  1. Math reference      : schoolbook negacyclic multiplication in Z_q[X]/(X^256+1)
  2. Algorithmic model   : Cooley-Tukey NTT / Gentleman-Sande INTT, same loop order
                           and twiddle indexing as the pq-crystals reference C code
  3. Hardware model      : bit-accurate copy of what the RTL does - Barrett or
                           Montgomery reduction, the 2P-bank conflict-free memory
                           map, the per-cycle lane schedule and the twiddle ROMs.

Everything is integer-exact; there is no floating point anywhere.
"""
from dataclasses import dataclass, field

N = 256
LOGN = 8


# --------------------------------------------------------------------------
# Scheme parameters
# --------------------------------------------------------------------------
@dataclass(frozen=True)
class Scheme:
    name: str
    q: int
    root: int      # primitive 256th (Kyber) / 512th (Dilithium) root of unity
    layers: int    # 7 for Kyber (incomplete NTT), 8 for Dilithium (complete)

    @property
    def w(self) -> int:
        """Coefficient width in bits (smallest W with q < 2^W)."""
        return self.q.bit_length()

    @property
    def n_zetas(self) -> int:
        return 1 << self.layers


KYBER = Scheme("kyber", 3329, 17, 7)
DILITHIUM = Scheme("dilithium", 8380417, 1753, 8)
SCHEMES = {"kyber": KYBER, "dilithium": DILITHIUM}


def brv(x: int, bits: int) -> int:
    return int(format(x, f"0{bits}b")[::-1], 2) if bits else 0


def zetas(s: Scheme):
    """Standard-domain twiddles, same index order as the reference tables."""
    return [pow(s.root, brv(i, s.layers), s.q) for i in range(s.n_zetas)]


def inv_twiddles(s: Scheme):
    """Inverse (GS) twiddle table, indexed the same way as the forward one:
    entry m+blk holds -zeta[2m-1-blk], where m = number of blocks in the layer."""
    z = zetas(s)
    t = [0] * s.n_zetas
    for i in range(1, s.n_zetas):
        m = 1 << (i.bit_length() - 1)
        blk = i - m
        t[i] = (-z[2 * m - 1 - blk]) % s.q
    return t


# --------------------------------------------------------------------------
# 1. Math reference
# --------------------------------------------------------------------------
def negacyclic_mul(a, b, q):
    r = [0] * N
    for i in range(N):
        if a[i] == 0:
            continue
        for j in range(N):
            k = i + j
            if k < N:
                r[k] = (r[k] + a[i] * b[j]) % q
            else:
                r[k - N] = (r[k - N] - a[i] * b[j]) % q
    return r


# --------------------------------------------------------------------------
# 2. Algorithmic model (mirrors pq-crystals loop structure)
# --------------------------------------------------------------------------
def ntt(a, s: Scheme):
    q, z = s.q, zetas(s)
    r = list(a)
    k = 1
    length = N // 2
    for _ in range(s.layers):
        start = 0
        while start < N:
            zeta = z[k]
            k += 1
            for j in range(start, start + length):
                t = zeta * r[j + length] % q
                r[j + length] = (r[j] - t) % q
                r[j] = (r[j] + t) % q
            start += 2 * length
        length >>= 1
    return r


def half(x, q):
    """x / 2 mod q for x in [0,q) - a shift and a conditional add in hardware."""
    return (x + q) >> 1 if x & 1 else x >> 1


def intt(a, s: Scheme):
    """GS inverse with the 1/2^layers scaling folded in as a /2 per layer."""
    q, wi = s.q, inv_twiddles(s)
    r = list(a)
    length = N >> s.layers
    for _ in range(s.layers):
        m = N // (2 * length)
        for j0 in range(0, N, 2 * length):
            w = wi[m + j0 // (2 * length)]
            for j in range(j0, j0 + length):
                x, y = r[j], r[j + length]
                r[j] = half((x + y) % q, q)
                r[j + length] = half((x - y) % q, q) * w % q
        length <<= 1
    return r


def pointwise(a_hat, b_hat, s: Scheme):
    """Multiply in the NTT domain. Dilithium: element-wise.
    Kyber: degree-1 base multiplication in Z_q[X]/(X^2 - zeta)."""
    q = s.q
    if s.layers == LOGN:
        return [x * y % q for x, y in zip(a_hat, b_hat)]
    z = zetas(s)
    r = [0] * N
    for i in range(N // 4):
        for sgn, off in ((1, 0), (-1, 2)):
            zeta = (sgn * z[64 + i]) % q
            a0, a1 = a_hat[4 * i + off], a_hat[4 * i + off + 1]
            b0, b1 = b_hat[4 * i + off], b_hat[4 * i + off + 1]
            r[4 * i + off] = (a1 * b1 % q * zeta + a0 * b0) % q
            r[4 * i + off + 1] = (a0 * b1 + a1 * b0) % q
    return r


# --------------------------------------------------------------------------
# 3. Hardware model
# --------------------------------------------------------------------------
@dataclass(frozen=True)
class Barrett:
    """r = p - floor(p*M / 2^K)*q, then one conditional subtract.
    With K = 2W and p < 2^(2W) the quotient estimate is off by at most 1."""
    s: Scheme

    @property
    def k(self):
        return 2 * self.s.w

    @property
    def m(self):
        return (1 << self.k) // self.s.q

    def twiddle(self, z):
        return z

    def mul(self, a, b):
        q = self.s.q
        p = a * b
        t = (p * self.m) >> self.k
        r = p - t * q
        assert 0 <= r < 2 * q, "Barrett bound violated"
        return r - q if r >= q else r


@dataclass(frozen=True)
class Montgomery:
    """REDC with R = 2^W:  m = (p mod R)*(-q^-1) mod R,  t = (p + m*q) / R,
    one conditional subtract. Twiddles are stored pre-multiplied by R."""
    s: Scheme

    @property
    def rbits(self):
        return self.s.w

    @property
    def qneg_inv(self):
        r = 1 << self.rbits
        return (-pow(self.s.q, -1, r)) % r

    def twiddle(self, z):
        return (z << self.rbits) % self.s.q

    def mul(self, a, b):
        q, rb = self.s.q, self.rbits
        mask = (1 << rb) - 1
        p = a * b
        m = ((p & mask) * self.qneg_inv) & mask
        t = (p + m * q) >> rb
        assert 0 <= t < 2 * q, "Montgomery bound violated"
        return t - q if t >= q else t


REDUCERS = {"barrett": Barrett, "montgomery": Montgomery}


def bank_of(i: int, b: int) -> int:
    """XOR-fold of the address in b-bit fields. Address bit p feeds bank bit p mod b."""
    if b == 0:
        return 0
    r = 0
    while i:
        r ^= i & ((1 << b) - 1)
        i >>= b
    return r


def lane_positions(k: int, b: int):
    """Address bits that vary across lanes in a cycle (besides butterfly bit k):
    one bit for every residue mod b other than k mod b, lowest such bit first."""
    pos = []
    for res in range(b):
        if res == k % b:
            continue
        pos.append(next(p for p in range(LOGN) if p % b == res))
    return pos


def deposit(val: int, positions):
    r = 0
    for n, p in enumerate(positions):
        if (val >> n) & 1:
            r |= 1 << p
    return r


def schedule(k: int, p_lanes: int):
    """Yield, per cycle, the list of (idx_a, idx_b) butterfly pairs for layer bit k."""
    b = (2 * p_lanes).bit_length() - 1
    lp = lane_positions(k, b)
    fixed = set(lp) | {k}
    free = [p for p in range(LOGN) if p not in fixed]
    for c in range(1 << len(free)):
        base = deposit(c, free)
        yield [(base | deposit(l, lp), base | deposit(l, lp) | (1 << k)) for l in range(p_lanes)]


@dataclass
class HwModel:
    """Cycle-schedule-accurate model of the accelerator datapath."""
    s: Scheme
    reduction: str = "barrett"
    p_lanes: int = 1
    bf_latency: int = 5     # butterfly pipeline depth (must match rtl/ntt_butterfly.v)
    rd_latency: int = 1     # registered bank read
    stats: dict = field(default_factory=dict)

    def __post_init__(self):
        assert self.p_lanes in (1, 2, 4, 8)
        self.red = REDUCERS[self.reduction](self.s)
        self.b = (2 * self.p_lanes).bit_length() - 1
        q = self.s.q
        self.tw_fwd = [self.red.twiddle(z) for z in zetas(self.s)]
        self.tw_inv = [self.red.twiddle(z) for z in inv_twiddles(self.s)]
        self.q = q

    # --- arithmetic units, exactly as in rtl/ntt_butterfly.v ---
    def addq(self, x, y):
        t = x + y
        return t - self.q if t >= self.q else t

    def subq(self, x, y):
        t = x - y
        return t + self.q if t < 0 else t

    def butterfly(self, a, b, w, inverse):
        if not inverse:                    # Cooley-Tukey
            t = self.red.mul(b, w)
            return self.addq(a, t), self.subq(a, t)
        x = half(self.addq(a, b), self.q)  # Gentleman-Sande, /2 per layer
        y = half(self.subq(a, b), self.q)
        return x, self.red.mul(y, w)

    def run(self, a, inverse=False):
        mem = {}                           # (bank, offset) -> value
        for i, v in enumerate(a):
            mem[(bank_of(i, self.b), i >> self.b)] = v
        ks = list(range(LOGN - 1, LOGN - 1 - self.s.layers, -1))   # forward: k = 7,6,...
        if inverse:
            ks.reverse()                                           # inverse: ...,6,7
        cycles = 0
        for k in ks:                       # butterfly distance 2^k
            m = (N // 2) >> k
            tw = self.tw_inv if inverse else self.tw_fwd
            for pairs in schedule(k, self.p_lanes):
                banks = [bank_of(i, self.b) for pr in pairs for i in pr]
                assert len(set(banks)) == len(banks), f"bank conflict k={k} {pairs}"
                for ia, ib in pairs:
                    w = tw[m + (ia >> (k + 1))]
                    ka, kb = (bank_of(ia, self.b), ia >> self.b), (bank_of(ib, self.b), ib >> self.b)
                    mem[ka], mem[kb] = self.butterfly(mem[ka], mem[kb], w, inverse)
                cycles += 1
            cycles += self.rd_latency + self.bf_latency      # pipeline drain between layers
        self.stats = {
            "compute_cycles": cycles,
            "io_cycles": 2 * (N // (2 * self.p_lanes)),
        }
        return [mem[(bank_of(i, self.b), i >> self.b)] for i in range(N)]


def cycle_count(s: Scheme, p_lanes: int, bf_latency=5, rd_latency=1):
    per_layer = (N // 2) // p_lanes + bf_latency + rd_latency
    return {"compute": s.layers * per_layer, "load": N // (2 * p_lanes), "unload": N // (2 * p_lanes)}
