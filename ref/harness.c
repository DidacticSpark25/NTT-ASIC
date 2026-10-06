/*
 * harness.c - drive the official pq-crystals reference NTT / inverse NTT
 * so the Python golden model can be cross-checked against it.
 *
 * Build (see ref/Makefile):
 *   kyber:     -DSCHEME_KYBER     with ref/kyber/{ntt,reduce}.c
 *   dilithium: -DSCHEME_DILITHIUM with ref/dilithium/{ntt,reduce}.c
 *
 * stdin : T, then T polynomials of 256 coefficients in [0,q)
 * stdout: for each polynomial, two lines:
 *           line 1: ntt(a)           fully reduced to [0,q)
 *           line 2: invntt(a)        Montgomery factor removed, reduced to [0,q)
 * The inverse is applied to the *input* (treated as an NTT-domain vector),
 * so forward and inverse are checked independently.
 */
#include <stdio.h>
#include <stdint.h>
#include "params.h"
#include "ntt.h"

#ifdef SCHEME_KYBER
typedef int16_t coef_t;
#define QQ KYBER_Q
#define RBITS 16
#define INV_FN(x) invntt(x)
#else
typedef int32_t coef_t;
#define QQ Q
#define RBITS 32
#define INV_FN(x) invntt_tomont(x)
#endif

static int64_t modq(int64_t x) { x %= QQ; if (x < 0) x += QQ; return x; }

static int64_t powmod(int64_t b, int64_t e) {
  int64_t r = 1; b = modq(b);
  while (e) { if (e & 1) r = (r * b) % QQ; b = (b * b) % QQ; e >>= 1; }
  return r;
}

int main(void) {
  int T;
  if (scanf("%d", &T) != 1) return 1;
  /* R^-1 mod q, used to strip the Montgomery factor left by invntt */
  int64_t R = powmod(2, RBITS);
  int64_t Rinv = powmod(R, QQ - 2);
  for (int t = 0; t < T; t++) {
    coef_t a[256], b[256];
    for (int i = 0; i < 256; i++) {
      long v; if (scanf("%ld", &v) != 1) return 1;
      a[i] = (coef_t)v; b[i] = (coef_t)v;
    }
    ntt(a);
    for (int i = 0; i < 256; i++) printf("%lld%c", (long long)modq(a[i]), i == 255 ? '\n' : ' ');
    INV_FN(b);
    for (int i = 0; i < 256; i++) printf("%lld%c", (long long)modq(modq(b[i]) * Rinv), i == 255 ? '\n' : ' ');
  }
  return 0;
}
