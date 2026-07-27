#include "ahc_rts.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <limits.h>
#include <string.h>
#include <string.h>

#ifdef AHC_USE_BOEHM
#include <gc.h>
#define AHC_ALLOC(n) GC_MALLOC(n)
#else
#define AHC_ALLOC(n) malloc(n)
#endif

void ahc_die(const char *msg) {
  fputs("ahc: ", stderr);
  fputs(msg, stderr);
  fputc('\n', stderr);
  exit(1);
}

static AhcNode *alloc_node(void) {
  AhcNode *n = (AhcNode *)AHC_ALLOC(sizeof(AhcNode));
  if (!n) ahc_die("out of memory");
  return n;
}

AhcNode **ahc_env(int n) {
  if (n == 0) return NULL;
  AhcNode **e = (AhcNode **)AHC_ALLOC(sizeof(AhcNode *) * n);
  if (!e) ahc_die("out of memory");
  return e;
}

AhcNode *ahc_mk_thunk(AhcCode code, AhcNode **env) {
  AhcNode *n = alloc_node();
  n->tag = AHC_THUNK; n->u.thunk.code = code; n->u.thunk.env = env;
  return n;
}

AhcNode *ahc_mk_fun(AhcFn fn, AhcNode **env) {
  AhcNode *n = alloc_node();
  n->tag = AHC_FUN; n->u.fun.fn = fn; n->u.fun.env = env;
  return n;
}

AhcNode *ahc_mk_int(long v) {
  AhcNode *n = alloc_node(); n->tag = AHC_INT; n->u.i = v; return n;
}

AhcNode *ahc_mk_double(double v) {
  AhcNode *n = alloc_node(); n->tag = AHC_DOUBLE; n->u.d = v; return n;
}

AhcNode *ahc_mk_char(long v) {
  AhcNode *n = alloc_node(); n->tag = AHC_CHAR; n->u.c = v; return n;
}

AhcNode *ahc_mk_ptr(void *p) {
  AhcNode *n = alloc_node(); n->tag = AHC_PTR; n->u.p = p; return n;
}

AhcNode *ahc_mk_con(int contag, int arity) {
  AhcNode *n = alloc_node();
  n->tag = AHC_CON; n->u.con.contag = contag; n->u.con.arity = arity;
  n->u.con.fields = arity ? ahc_env(arity) : NULL;
  return n;
}

/* Update-in-place graph reduction: the PRD's thunk model. */
AhcNode *ahc_eval(AhcNode *n) {
  for (;;) {
    switch (n->tag) {
    case AHC_IND:
      n = n->u.ind;
      break;
    case AHC_THUNK: {
      AhcCode code = n->u.thunk.code;
      AhcNode **env = n->u.thunk.env;
      n->tag = AHC_BLACKHOLE;
      AhcNode *v = ahc_eval(code(env));
      n->tag = AHC_IND;
      n->u.ind = v;
      n = v;
      break;
    }
    case AHC_BLACKHOLE:
      ahc_die("<<loop>>");
    default:
      return n;
    }
  }
}

AhcNode *ahc_apply(AhcNode *f, AhcNode *a) {
  AhcNode *w = ahc_eval(f);
  if (w->tag != AHC_FUN) ahc_die("applied a non-function");
  return w->u.fun.fn(w->u.fun.env, a);
}

/* Constructor worker: env = [tagbox, aritybox, collected...]. */
static AhcNode *con_collect(AhcNode **env, AhcNode *arg) {
  long contag = env[0]->u.i, arity = env[1]->u.i;
  long have = 0;
  while (env[2 + have] != NULL) have++;
  if (have + 1 == arity) {
    AhcNode *c = ahc_mk_con((int)contag, (int)arity);
    for (long i = 0; i < have; i++) c->u.con.fields[i] = env[2 + i];
    c->u.con.fields[have] = arg;
    return c;
  }
  AhcNode **e2 = ahc_env((int)(2 + arity));
  e2[0] = env[0]; e2[1] = env[1];
  for (long i = 0; i < have; i++) e2[2 + i] = env[2 + i];
  e2[2 + have] = arg;
  for (long i = have + 1; i < arity; i++) e2[2 + i] = NULL;
  return ahc_mk_fun(con_collect, e2);
}

AhcNode *ahc_mk_confun(int contag, int arity) {
  if (arity == 0) return ahc_mk_con(contag, 0);
  AhcNode **e = ahc_env(2 + arity);
  e[0] = ahc_mk_int(contag); e[1] = ahc_mk_int(arity);
  for (int i = 0; i < arity; i++) e[2 + i] = NULL;
  return ahc_mk_fun(con_collect, e);
}

/* Dictionary field selector. */
static AhcNode *sel_fn(AhcNode **env, AhcNode *arg) {
  AhcNode *d = ahc_eval(arg);
  if (d->tag != AHC_CON) ahc_die("selector on a non-dictionary");
  long idx = env[0]->u.i;
  if (idx >= d->u.con.arity) ahc_die("selector out of range");
  return d->u.con.fields[idx];
}

static AhcNode *missing_code(AhcNode **env) {
  ahc_die((const char *)(uintptr_t)env[0]->u.i);
}

AhcNode *ahc_mk_missing(const char *what) {
  AhcNode **e = ahc_env(1);
  e[0] = ahc_mk_int((long)(uintptr_t)what);
  return ahc_mk_thunk(missing_code, e);
}

AhcNode *ahc_mk_selector(int index) {
  AhcNode **e = ahc_env(1);
  e[0] = ahc_mk_int(index);
  return ahc_mk_fun(sel_fn, e);
}

/* Lists: [] = 1, (:) = 2 (AHC.Builtins tags). */
#define NIL_TAG 1
#define CONS_TAG 2
#define FALSE_TAG 1
#define TRUE_TAG 2
#define UNIT_TAG 1

static AhcNode *mk_bool(int b) {
  return ahc_mk_con(b ? TRUE_TAG : FALSE_TAG, 0);
}

AhcNode *ahc_mk_string(const char *s) {
  size_t len = strlen(s);
  AhcNode *acc = ahc_mk_con(NIL_TAG, 0);
  for (size_t i = len; i > 0; i--) {
    AhcNode *c = ahc_mk_con(CONS_TAG, 2);
    c->u.con.fields[0] = ahc_mk_char((unsigned char)s[i - 1]);
    c->u.con.fields[1] = acc;
    acc = c;
  }
  return acc;
}

/* ----- Integer bignum -------------------------------------------- */
/* Sign+magnitude, uint32 limbs little-endian. CANONICAL FORM: any
   value that fits a C long lives in an AHC_INT node; AHC_BIGINT
   appears only beyond long range. All integer prims accept both. */

typedef uint32_t limb;

static limb *limb_alloc(int n) {
  limb *d = (limb *)AHC_ALLOC(sizeof(limb) * (n > 0 ? n : 1));
  if (!d) ahc_die("out of memory");
  return d;
}

static int mag_norm(const limb *d, int n) {
  while (n > 0 && d[n - 1] == 0) n--;
  return n;
}

static int mag_cmp(const limb *a, int na, const limb *b, int nb) {
  if (na != nb) return na > nb ? 1 : -1;
  for (int i = na - 1; i >= 0; i--)
    if (a[i] != b[i]) return a[i] > b[i] ? 1 : -1;
  return 0;
}

/* Build the canonical node for sign * d[0..n). */
static AhcNode *mk_big(int sign, limb *d, int n) {
  n = mag_norm(d, n);
  if (n == 0) return ahc_mk_int(0);
  if (n <= 2) {
    unsigned long v = d[0];
    if (n == 2) v |= (unsigned long)d[1] << 32;
    if (sign > 0 && v <= (unsigned long)LONG_MAX)
      return ahc_mk_int((long)v);
    if (sign < 0 && v <= (unsigned long)LONG_MAX + 1)
      return ahc_mk_int((long)(0UL - v));
  }
  {
    AhcNode *r = alloc_node();
    r->tag = AHC_BIGINT;
    r->u.big.sign = sign;
    r->u.big.n = n;
    r->u.big.d = d;
    return r;
  }
}

/* An unsigned 64-bit C result: fast long path, bignum above
   LONG_MAX (the FFI's Word64 boxing). */
AhcNode *ahc_mk_ulong(unsigned long v) {
  limb *d;
  if (v <= (unsigned long)LONG_MAX) return ahc_mk_int((long)v);
  d = (limb *)AHC_ALLOC(2 * sizeof(limb));
  if (!d) ahc_die("out of memory");
  d[0] = (limb)(v & 0xffffffffUL);
  d[1] = (limb)(v >> 32);
  return mk_big(1, d, 2);
}

typedef struct { int sign; int n; const limb *d; } BigView;

/* View an evaluated INT/BIGINT node; tmp backs the INT case. */
static BigView big_view(AhcNode *v, limb tmp[2]) {
  BigView r;
  if (v->tag == AHC_BIGINT) {
    r.sign = v->u.big.sign; r.n = v->u.big.n; r.d = v->u.big.d;
    return r;
  }
  {
    long x = v->u.i;
    unsigned long m = x < 0 ? 0UL - (unsigned long)x
                            : (unsigned long)x;
    tmp[0] = (limb)m; tmp[1] = (limb)(m >> 32);
    r.sign = x > 0 ? 1 : x < 0 ? -1 : 0;
    r.n = mag_norm(tmp, 2); r.d = tmp;
    return r;
  }
}

static limb *mag_add(const limb *a, int na, const limb *b, int nb,
                     int *nr) {
  int n = (na > nb ? na : nb) + 1, i;
  limb *r = limb_alloc(n);
  uint64_t carry = 0;
  for (i = 0; i < n - 1; i++) {
    uint64_t s = carry + (i < na ? a[i] : 0) + (i < nb ? b[i] : 0);
    r[i] = (limb)s; carry = s >> 32;
  }
  r[n - 1] = (limb)carry;
  *nr = n;
  return r;
}

/* a - b, requires |a| >= |b|. */
static limb *mag_sub(const limb *a, int na, const limb *b, int nb,
                     int *nr) {
  limb *r = limb_alloc(na);
  int64_t borrow = 0;
  for (int i = 0; i < na; i++) {
    int64_t s = (int64_t)a[i] - (i < nb ? b[i] : 0) - borrow;
    borrow = s < 0;
    r[i] = (limb)(s + (borrow ? ((int64_t)1 << 32) : 0));
  }
  *nr = na;
  return r;
}

static limb *mag_mul(const limb *a, int na, const limb *b, int nb,
                     int *nr) {
  int n = na + nb, i, j;
  limb *r = limb_alloc(n);
  for (i = 0; i < n; i++) r[i] = 0;
  for (i = 0; i < na; i++) {
    uint64_t carry = 0;
    for (j = 0; j < nb; j++) {
      uint64_t s = (uint64_t)a[i] * b[j] + r[i + j] + carry;
      r[i + j] = (limb)s; carry = s >> 32;
    }
    r[i + nb] = (limb)carry;
  }
  *nr = n;
  return r;
}

/* Binary long division: |a| = q*|b| + r with 0 <= r < |b|. */
static void mag_divmod(const limb *a, int na, const limb *b, int nb,
                       limb **q_out, int *nq, limb **r_out, int *nr) {
  limb *q = limb_alloc(na > 0 ? na : 1);
  limb *r = limb_alloc(nb + 1);
  int i, bit;
  for (i = 0; i < na; i++) q[i] = 0;
  for (i = 0; i < nb + 1; i++) r[i] = 0;
  for (i = na - 1; i >= 0; i--)
    for (bit = 31; bit >= 0; bit--) {
      /* r = (r << 1) | next bit of a */
      uint32_t carry = (a[i] >> bit) & 1u;
      for (int k = 0; k < nb + 1; k++) {
        uint32_t nc = r[k] >> 31;
        r[k] = (r[k] << 1) | carry;
        carry = nc;
      }
      if (mag_cmp(r, mag_norm(r, nb + 1), b, nb) >= 0) {
        int64_t borrow = 0;
        for (int k = 0; k < nb + 1; k++) {
          int64_t s = (int64_t)r[k] - (k < nb ? b[k] : 0) - borrow;
          borrow = s < 0;
          r[k] = (limb)(s + (borrow ? ((int64_t)1 << 32) : 0));
        }
        q[i] |= 1u << bit;
      }
    }
  *q_out = q; *nq = na > 0 ? na : 1;
  *r_out = r; *nr = nb + 1;
}

/* In-place divide by a small divisor, returning the remainder. */
static limb mag_divmod_small(limb *a, int n, limb m) {
  uint64_t rem = 0;
  for (int i = n - 1; i >= 0; i--) {
    uint64_t cur = (rem << 32) | a[i];
    a[i] = (limb)(cur / m);
    rem = cur % m;
  }
  return (limb)rem;
}

/* Signed helpers over evaluated nodes. */
static AhcNode *big_add_sv(BigView A, BigView B) {
  int n;
  limb *r;
  if (A.sign == 0) {
    r = limb_alloc(B.n > 0 ? B.n : 1);
    for (int i = 0; i < B.n; i++) r[i] = B.d[i];
    return mk_big(B.sign, r, B.n);
  }
  if (B.sign == 0) {
    r = limb_alloc(A.n > 0 ? A.n : 1);
    for (int i = 0; i < A.n; i++) r[i] = A.d[i];
    return mk_big(A.sign, r, A.n);
  }
  if (A.sign == B.sign) {
    r = mag_add(A.d, A.n, B.d, B.n, &n);
    return mk_big(A.sign, r, n);
  }
  {
    int c = mag_cmp(A.d, A.n, B.d, B.n);
    if (c == 0) return ahc_mk_int(0);
    if (c > 0) {
      r = mag_sub(A.d, A.n, B.d, B.n, &n);
      return mk_big(A.sign, r, n);
    }
    r = mag_sub(B.d, B.n, A.d, A.n, &n);
    return mk_big(B.sign, r, n);
  }
}

static BigView big_negv(BigView A) { A.sign = -A.sign; return A; }

static int big_cmp_sv(BigView A, BigView B) {
  if (A.sign != B.sign) return A.sign > B.sign ? 1 : -1;
  {
    int c = mag_cmp(A.d, A.n, B.d, B.n);
    return A.sign >= 0 ? c : -c;
  }
}

/* Compare two evaluated integer nodes of either representation. */
static int int_cmp(AhcNode *a, AhcNode *b) {
  limb t1[2], t2[2];
  if (a->tag == AHC_INT && b->tag == AHC_INT)
    return (a->u.i > b->u.i) - (a->u.i < b->u.i);
  return big_cmp_sv(big_view(a, t1), big_view(b, t2));
}

/* Truncated division of evaluated nodes (both may be big);
   quotient/remainder returned as canonical nodes. */
static void big_quotrem(AhcNode *a, AhcNode *b,
                        AhcNode **q_node, AhcNode **r_node) {
  limb t1[2], t2[2];
  BigView A = big_view(a, t1), B = big_view(b, t2);
  limb *q, *r;
  int nq, nr;
  if (B.sign == 0) ahc_die("divide by zero");
  if (A.sign == 0) { *q_node = ahc_mk_int(0); *r_node = ahc_mk_int(0); return; }
  mag_divmod(A.d, A.n, B.d, B.n, &q, &nq, &r, &nr);
  *q_node = mk_big(A.sign * B.sign, q, nq);
  *r_node = mk_big(A.sign, r, nr);
}

/* ----- exact rational literals (Report 6.4) ----------------------
   A float literal compiles to ahc_mk_ratlit(tag, "num", "den"):
   an exact numerator/denominator pair carried as a Ratio-shaped
   CON node (codegen supplies :%'s tag), so `2.5 :: Rational` is
   exactly 25/10 and Data.Ratio's source fromRational reduces it.
   Fractional Double's fromRational converts the pair with ONE
   round-to-nearest-even, so Double literals keep strtod-exact
   values. (Known limit: literals rounding into the subnormal
   range may double-round via ldexp - far outside any oracle
   test.) */

static AhcNode *int_from_dec(const char *sdec) {
  size_t len = strlen(sdec);
  if (len < 19) {
    return ahc_mk_int(strtol(sdec, NULL, 10));
  }
  return ahc_mk_big_str(sdec);
}

AhcNode *ahc_mk_ratlit(long contag, const char *n, const char *d) {
  AhcNode *r = ahc_mk_con(contag, 2);
  r->u.con.fields[0] = int_from_dec(n);
  r->u.con.fields[1] = int_from_dec(d);
  return r;
}

static int view_bitlen(BigView V) {
  int b;
  limb top;
  if (V.sign == 0) return 0;
  b = 32 * (V.n - 1);
  top = V.d[V.n - 1];
  while (top) { b++; top >>= 1; }
  return b;
}

/* node * 2^shift as a fresh canonical node (shift >= 0). */
static AhcNode *node_shl(AhcNode *a, int shift) {
  limb t[2];
  BigView A = big_view(a, t);
  int words = shift / 32, bits = shift % 32;
  int n = A.n + words + 1;
  limb *d = (limb *)AHC_ALLOC(sizeof(limb) * n);
  int i;
  for (i = 0; i < n; i++) d[i] = 0;
  for (i = 0; i < A.n; i++) {
    d[i + words] |= (limb)(((unsigned long)A.d[i] << bits)
                           & 0xFFFFFFFFUL);
    if (bits)
      d[i + words + 1] |=
        (limb)((unsigned long)A.d[i] >> (32 - bits));
  }
  return mk_big(A.sign, d, n);
}

static int fits_double_exact(AhcNode *e, double *out) {
  if (e->tag == AHC_INT) {
    long v = e->u.i;
    if (v >= -(1L << 53) && v <= (1L << 53)) {
      *out = (double)v;
      return 1;
    }
    return 0;
  }
  {
    limb t[2];
    BigView V = big_view(e, t);
    if (view_bitlen(V) <= 53) {
      double v = 0;
      int i;
      for (i = V.n - 1; i >= 0; i--) v = v * 4294967296.0 + V.d[i];
      *out = V.sign < 0 ? -v : v;
      return 1;
    }
    return 0;
  }
}

static double rat_to_double(AhcNode *n, AhcNode *d) {
  double dn, dd;
  if (fits_double_exact(n, &dn) && fits_double_exact(d, &dd))
    return dn / dd;      /* both exact: one IEEE rounding */
  {
    limb t1[2], t2[2];
    BigView N = big_view(n, t1), D = big_view(d, t2);
    int bn = view_bitlen(N), bd = view_bitlen(D);
    int shift = 55 - (bn - bd);
    AhcNode *ns = n, *ds = d, *q, *r;
    unsigned long qv = 0;
    int sticky, nb, lo, k;
    unsigned long mant;
    if (N.sign == 0) return 0.0;
    if (shift > 0) ns = node_shl(n, shift);
    else if (shift < 0) ds = node_shl(d, -shift);
    big_quotrem(ns, ds, &q, &r);
    sticky = !(r->tag == AHC_INT && r->u.i == 0);
    /* MAGNITUDE of q: literal pairs are positive, but a computed
       Rational's numerator is signed and rides through quotrem
       (fuzzer find, seed 205 - the sign bits corrupted the
       mantissa extraction). */
    if (q->tag == AHC_INT) {
      long v = q->u.i;
      qv = (unsigned long)(v < 0 ? -v : v);
    } else {
      limb t3[2];
      BigView Q = big_view(q, t3);
      int i;
      for (i = Q.n - 1; i >= 0; i--) qv = (qv << 32) | Q.d[i];
    }
    nb = 0;
    { unsigned long x = qv; while (x) { nb++; x >>= 1; } }
    lo = nb - 53;            /* > 0 by construction (>= 54 bits) */
    mant = qv >> lo;
    if ((qv >> (lo - 1)) & 1UL) {          /* round bit */
      if (sticky || (qv & ((1UL << (lo - 1)) - 1UL))
          || (mant & 1UL))
        mant++;
    }
    k = (nb - 53) - shift;
    {
      double v = ldexp((double)mant, k);
      return (N.sign < 0) != (D.sign < 0) ? -v : v;
    }
  }
}

static AhcNode *p_from_rational_d(AhcNode *a) {
  AhcNode *e = ahc_eval(a);
  if (e->tag == AHC_DOUBLE) return e;   /* legacy literal path */
  {
    AhcNode *n = ahc_eval(e->u.con.fields[0]);
    AhcNode *d = ahc_eval(e->u.con.fields[1]);
    return ahc_mk_double(rat_to_double(n, d));
  }
}

/* Report 6.4.2: div/mod floor toward negative infinity. */
static void big_divmod_fl(AhcNode *a, AhcNode *b,
                          AhcNode **q_node, AhcNode **r_node) {
  AhcNode *q, *r;
  limb t1[2], t2[2], t3[2];
  big_quotrem(a, b, &q, &r);
  {
    BigView R = big_view(r, t1);
    BigView A = big_view(a, t2), B = big_view(b, t3);
    if (R.sign != 0 && A.sign * B.sign < 0) {
      limb one[1] = {1};
      BigView ONE; ONE.sign = -1; ONE.n = 1; ONE.d = one;
      limb tq[2];
      q = big_add_sv(big_view(q, tq), ONE);            /* q - 1 */
      {
        limb tr[2], tb[2];
        r = big_add_sv(big_view(r, tr), big_view(b, tb)); /* r + b */
      }
    }
  }
  *q_node = q; *r_node = r;
}

/* Literal beyond long range: parse the lexeme (dec/hex/oct,
   optional leading '-') into a canonical node. */
AhcNode *ahc_mk_big_str(const char *s) {
  int sign = 1, base = 10, cap = 4, n = 0;
  limb *d;
  if (*s == '-') { sign = -1; s++; }
  if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) { base = 16; s += 2; }
  else if (s[0] == '0' && (s[1] == 'o' || s[1] == 'O')) { base = 8; s += 2; }
  d = limb_alloc(cap);
  for (; *s; s++) {
    uint64_t carry;
    int digit = *s >= '0' && *s <= '9' ? *s - '0'
              : *s >= 'a' && *s <= 'f' ? *s - 'a' + 10
              : *s >= 'A' && *s <= 'F' ? *s - 'A' + 10 : -1;
    if (digit < 0) continue;
    carry = digit;
    for (int i = 0; i < n; i++) {
      uint64_t cur = (uint64_t)d[i] * base + carry;
      d[i] = (limb)cur; carry = cur >> 32;
    }
    if (carry) {
      if (n == cap) {
        limb *nd = limb_alloc(cap * 2);
        for (int i = 0; i < n; i++) nd[i] = d[i];
        d = nd; cap *= 2;
      }
      d[n++] = (limb)carry;
    }
  }
  return mk_big(sign, d, n);
}

/* Decimal image of an evaluated integer node into a StrBuf-free
   static-capable buffer; caller frees. */
static char *big_image(AhcNode *v) {
  limb t[2];
  BigView A;
  limb *w;
  char *out, *tmp;
  int n, i, pos = 0, tl = 0;
  if (v->tag == AHC_INT) {
    out = malloc(32);
    if (!out) ahc_die("out of memory");
    snprintf(out, 32, "%ld", v->u.i);
    return out;
  }
  A = big_view(v, t);
  w = limb_alloc(A.n);
  for (i = 0; i < A.n; i++) w[i] = A.d[i];
  n = A.n;
  /* peel 9 decimal digits at a time, least significant group first;
     every group except the final (most significant) one is written
     zero-padded to exactly 9 chars */
  tmp = malloc(10 * ((size_t)A.n + 2));
  out = malloc(10 * ((size_t)A.n + 2) + 2);
  if (!tmp || !out) ahc_die("out of memory");
  while (mag_norm(w, n) > 0) {
    limb rch = mag_divmod_small(w, n, 1000000000u);
    n = mag_norm(w, n);
    tl += snprintf(tmp + tl, 11, n > 0 ? "%09u" : "%u", rch);
  }
  if (A.sign < 0) out[pos++] = '-';
  {
    /* groups start at multiples of 9; emit in reverse order */
    int gcount = (tl + 8) / 9;
    int lastlen = tl - (gcount - 1) * 9;
    for (i = gcount - 1; i >= 0; i--) {
      int len = (i == gcount - 1) ? lastlen : 9;
      memcpy(out + pos, tmp + i * 9, (size_t)len);
      pos += len;
    }
    out[pos] = 0;
  }
  free(tmp);
  return out;
}

/* ----- primitives ------------------------------------------------ */

typedef AhcNode *(*Prim2)(AhcNode *, AhcNode *);

static AhcNode *prim2_apply(AhcNode **env, AhcNode *b) {
  Prim2 f = (Prim2)(uintptr_t)env[0]->u.i;
  return f(env[1], b);
}

static AhcNode *prim2_first(AhcNode **env, AhcNode *a) {
  AhcNode **e2 = ahc_env(2);
  e2[0] = env[0]; e2[1] = a;
  return ahc_mk_fun(prim2_apply, e2);
}

static AhcNode *mk_prim2(Prim2 f) {
  AhcNode **e = ahc_env(1);
  e[0] = ahc_mk_int((long)(uintptr_t)f);
  return ahc_mk_fun(prim2_first, e);
}

typedef AhcNode *(*Prim3)(AhcNode *, AhcNode *, AhcNode *);

static AhcNode *prim3_apply3(AhcNode **env, AhcNode *c) {
  Prim3 f = (Prim3)(uintptr_t)env[0]->u.i;
  return f(env[1], env[2], c);
}

static AhcNode *prim3_apply2(AhcNode **env, AhcNode *b) {
  AhcNode **e3 = ahc_env(3);
  e3[0] = env[0]; e3[1] = env[1]; e3[2] = b;
  return ahc_mk_fun(prim3_apply3, e3);
}

static AhcNode *prim3_first(AhcNode **env, AhcNode *a) {
  AhcNode **e2 = ahc_env(2);
  e2[0] = env[0]; e2[1] = a;
  return ahc_mk_fun(prim3_apply2, e2);
}

static AhcNode *mk_prim3(Prim3 f) {
  AhcNode **e = ahc_env(1);
  e[0] = ahc_mk_int((long)(uintptr_t)f);
  return ahc_mk_fun(prim3_first, e);
}

typedef AhcNode *(*Prim1)(AhcNode *);

static AhcNode *prim1_apply(AhcNode **env, AhcNode *a) {
  Prim1 f = (Prim1)(uintptr_t)env[0]->u.i;
  return f(a);
}

static AhcNode *mk_prim1(Prim1 f) {
  AhcNode **e = ahc_env(1);
  e[0] = ahc_mk_int((long)(uintptr_t)f);
  return ahc_mk_fun(prim1_apply, e);
}

/* General-arity prim: env = [fnbox, aritybox, collected...], like
   con_collect. When saturated, the args (still unevaluated) are
   handed to f as an array. */
static AhcNode *primn_collect(AhcNode **env, AhcNode *arg) {
  long arity = env[1]->u.i;
  long have = 0;
  while (env[2 + have] != NULL) have++;
  if (have + 1 == arity) {
    AhcPrimN f = (AhcPrimN)(uintptr_t)env[0]->u.i;
    AhcNode **args = ahc_env((int)arity);
    for (long i = 0; i < have; i++) args[i] = env[2 + i];
    args[have] = arg;
    return f(args);
  }
  AhcNode **e2 = ahc_env((int)(2 + arity));
  e2[0] = env[0]; e2[1] = env[1];
  for (long i = 0; i < have; i++) e2[2 + i] = env[2 + i];
  e2[2 + have] = arg;
  for (long i = have + 1; i < arity; i++) e2[2 + i] = NULL;
  return ahc_mk_fun(primn_collect, e2);
}

AhcNode *ahc_mk_primn(int arity, AhcPrimN f) {
  AhcNode **e;
  if (arity < 1) ahc_die("ahc_mk_primn: arity < 1");
  e = ahc_env(2 + arity);
  e[0] = ahc_mk_int((long)(uintptr_t)f);
  e[1] = ahc_mk_int(arity);
  for (int i = 0; i < arity; i++) e[2 + i] = NULL;
  return ahc_mk_fun(primn_collect, e);
}

/* Integer arithmetic: fast long path, promoting to bignum on
   overflow; every prim accepts either representation. */

static AhcNode *p_add(AhcNode *a, AhcNode *b) {
  AhcNode *ea = ahc_eval(a), *eb = ahc_eval(b);
  limb t1[2], t2[2];
  if (ea->tag == AHC_INT && eb->tag == AHC_INT) {
    long r;
    if (!__builtin_add_overflow(ea->u.i, eb->u.i, &r))
      return ahc_mk_int(r);
  }
  return big_add_sv(big_view(ea, t1), big_view(eb, t2));
}

static AhcNode *p_sub(AhcNode *a, AhcNode *b) {
  AhcNode *ea = ahc_eval(a), *eb = ahc_eval(b);
  limb t1[2], t2[2];
  if (ea->tag == AHC_INT && eb->tag == AHC_INT) {
    long r;
    if (!__builtin_sub_overflow(ea->u.i, eb->u.i, &r))
      return ahc_mk_int(r);
  }
  return big_add_sv(big_view(ea, t1), big_negv(big_view(eb, t2)));
}

static AhcNode *p_mul(AhcNode *a, AhcNode *b) {
  AhcNode *ea = ahc_eval(a), *eb = ahc_eval(b);
  limb t1[2], t2[2];
  if (ea->tag == AHC_INT && eb->tag == AHC_INT) {
    long r;
    if (!__builtin_mul_overflow(ea->u.i, eb->u.i, &r))
      return ahc_mk_int(r);
  }
  {
    BigView A = big_view(ea, t1), B = big_view(eb, t2);
    int n;
    limb *r;
    if (A.sign == 0 || B.sign == 0) return ahc_mk_int(0);
    r = mag_mul(A.d, A.n, B.d, B.n, &n);
    return mk_big(A.sign * B.sign, r, n);
  }
}

static AhcNode *p_div(AhcNode *a, AhcNode *b) {
  AhcNode *ea = ahc_eval(a), *eb = ahc_eval(b);
  if (ea->tag == AHC_INT && eb->tag == AHC_INT) {
    long x = ea->u.i, y = eb->u.i;
    if (y == 0) ahc_die("divide by zero");
    if (!(x == LONG_MIN && y == -1))
      return ahc_mk_int((x % y != 0 && ((x < 0) != (y < 0)))
                          ? x / y - 1 : x / y);
  }
  {
    AhcNode *q, *r;
    big_divmod_fl(ea, eb, &q, &r);
    return q;
  }
}

static AhcNode *p_mod(AhcNode *a, AhcNode *b) {
  AhcNode *ea = ahc_eval(a), *eb = ahc_eval(b);
  if (ea->tag == AHC_INT && eb->tag == AHC_INT) {
    long x = ea->u.i, y = eb->u.i;
    if (y == 0) ahc_die("divide by zero");
    if (!(x == LONG_MIN && y == -1)) {
      /* Floor-adjust ONLY when the signs differ. The textbook
         ((x%y)+y)%y overflows when x%y and y are both large and
         positive - 7.4e18 `mod` 8.2e18 wrapped NEGATIVE (fuzzer
         find, seed 6215, which surfaced as a wrong gcd and a
         mis-reduced Rational). With opposite signs
         |r+y| < max(|r|,|y|), so this addition cannot overflow. */
      long r = x % y;
      if (r != 0 && ((r < 0) != (y < 0))) r += y;
      return ahc_mk_int(r);
    }
  }
  {
    AhcNode *q, *r;
    big_divmod_fl(ea, eb, &q, &r);
    return r;
  }
}

static AhcNode *p_quot(AhcNode *a, AhcNode *b) {
  AhcNode *ea = ahc_eval(a), *eb = ahc_eval(b);
  if (ea->tag == AHC_INT && eb->tag == AHC_INT) {
    long x = ea->u.i, y = eb->u.i;
    if (y == 0) ahc_die("divide by zero");
    if (!(x == LONG_MIN && y == -1)) return ahc_mk_int(x / y);
  }
  {
    AhcNode *q, *r;
    big_quotrem(ea, eb, &q, &r);
    return q;
  }
}

static AhcNode *p_rem(AhcNode *a, AhcNode *b) {
  AhcNode *ea = ahc_eval(a), *eb = ahc_eval(b);
  if (ea->tag == AHC_INT && eb->tag == AHC_INT) {
    long x = ea->u.i, y = eb->u.i;
    if (y == 0) ahc_die("divide by zero");
    if (!(x == LONG_MIN && y == -1)) return ahc_mk_int(x % y);
  }
  {
    AhcNode *q, *r;
    big_quotrem(ea, eb, &q, &r);
    return r;
  }
}

#define ICMP(name, op)                                                \
  static AhcNode *name(AhcNode *a, AhcNode *b) {                      \
    return mk_bool(int_cmp(ahc_eval(a), ahc_eval(b)) op 0);           \
  }

ICMP(p_eq, ==)
ICMP(p_ne, !=)
ICMP(p_lt, <)
ICMP(p_le, <=)
ICMP(p_gt, >)
ICMP(p_ge, >=)

static AhcNode *p_neg(AhcNode *a) {
  AhcNode *e = ahc_eval(a);
  limb t[2];
  if (e->tag == AHC_INT && e->u.i != LONG_MIN)
    return ahc_mk_int(-e->u.i);
  {
    BigView A = big_negv(big_view(e, t));
    limb *r = limb_alloc(A.n > 0 ? A.n : 1);
    for (int i = 0; i < A.n; i++) r[i] = A.d[i];
    return mk_big(A.sign, r, A.n);
  }
}
static AhcNode *p_abs(AhcNode *a) {
  AhcNode *e = ahc_eval(a);
  if (e->tag == AHC_INT)
    return e->u.i >= 0 ? e
           : e->u.i != LONG_MIN ? ahc_mk_int(-e->u.i) : p_neg(a);
  return e->u.big.sign >= 0 ? e : p_neg(a);
}
static AhcNode *p_signum(AhcNode *a) {
  AhcNode *e = ahc_eval(a);
  long s = e->tag == AHC_INT
             ? (e->u.i > 0 ? 1 : e->u.i < 0 ? -1 : 0)
             : e->u.big.sign;
  return ahc_mk_int(s);
}
/* fromInteger at Int/Integer: identity on the canonical value (Int
   overflow behavior is undefined per the Report; we keep the exact
   value). */
static AhcNode *p_from_integer(AhcNode *a) { return a; }
static AhcNode *p_ord(AhcNode *a) { return ahc_mk_int(ahc_eval(a)->u.c); }
static AhcNode *p_chr(AhcNode *a) { return ahc_mk_char(ahc_eval(a)->u.i); }

static AhcNode *p_eq_char(AhcNode *a, AhcNode *b) {
  return mk_bool(ahc_eval(a)->u.c == ahc_eval(b)->u.c);
}
static AhcNode *p_lt_char(AhcNode *a, AhcNode *b) {
  return mk_bool(ahc_eval(a)->u.c < ahc_eval(b)->u.c);
}

static AhcNode *p_show_int(AhcNode *a) {
  char *img = big_image(ahc_eval(a));
  AhcNode *r = ahc_mk_string(img);
  free(img);
  return r;
}
/* Report 11.4 (Show Char): common escapes by name, other
   non-printables as decimal escapes. */
static AhcNode *p_show_char(AhcNode *a) {
  long v = ahc_eval(a)->u.c;
  char buf[16];
  switch (v) {
  case '\n': return ahc_mk_string("'\\n'");
  case '\t': return ahc_mk_string("'\\t'");
  case '\r': return ahc_mk_string("'\\r'");
  case '\\': return ahc_mk_string("'\\\\'");
  case '\'': return ahc_mk_string("'\\''");
  default:
    if (v >= 32 && v <= 126)
      snprintf(buf, sizeof buf, "'%c'", (char)v);
    else
      snprintf(buf, sizeof buf, "'\\%ld'", v);
    return ahc_mk_string(buf);
  }
}
static AhcNode *p_show_bool(AhcNode *a) {
  return ahc_mk_string(ahc_eval(a)->u.con.contag == TRUE_TAG
                         ? "True" : "False");
}

/* Structural equality/ordering over WHNF-forced values: covers Eq
 * and Ord for Int/Integer/Char/Bool and every first-order ADT
 * (deriving-friendly). */
static int poly_cmp(AhcNode *a, AhcNode *b) {
  a = ahc_eval(a); b = ahc_eval(b);
  if ((a->tag == AHC_INT || a->tag == AHC_BIGINT) &&
      (b->tag == AHC_INT || b->tag == AHC_BIGINT))
    return int_cmp(a, b);
  if (a->tag != b->tag) ahc_die("comparing different runtime shapes");
  switch (a->tag) {
  case AHC_INT:
    return (a->u.i > b->u.i) - (a->u.i < b->u.i);
  case AHC_DOUBLE:
    return (a->u.d > b->u.d) - (a->u.d < b->u.d);
  case AHC_CHAR:
    return (a->u.c > b->u.c) - (a->u.c < b->u.c);
  case AHC_CON: {
    if (a->u.con.contag != b->u.con.contag)
      return (a->u.con.contag > b->u.con.contag) -
             (a->u.con.contag < b->u.con.contag);
    for (int i = 0; i < a->u.con.arity; i++) {
      int c = poly_cmp(a->u.con.fields[i], b->u.con.fields[i]);
      if (c != 0) return c;
    }
    return 0;
  }
  case AHC_PTR:
    return ((uintptr_t)a->u.p > (uintptr_t)b->u.p) -
           ((uintptr_t)a->u.p < (uintptr_t)b->u.p);
  default:
    ahc_die("comparing functions");
  }
}

#define LT_TAG 1
#define EQ_TAG 2
#define GT_TAG 3

static AhcNode *p_eq_poly(AhcNode *a, AhcNode *b) {
  return mk_bool(poly_cmp(a, b) == 0);
}

static AhcNode *p_compare_poly(AhcNode *a, AhcNode *b) {
  int c = poly_cmp(a, b);
  return ahc_mk_con(c < 0 ? LT_TAG : (c == 0 ? EQ_TAG : GT_TAG), 0);
}

/* enumFrom n = n : enumFrom (n+1), lazily. */
static AhcNode *enum_from_code(AhcNode **env);

static AhcNode *mk_enum_from(long n) {
  AhcNode **e = ahc_env(1);
  e[0] = ahc_mk_int(n);
  return ahc_mk_thunk(enum_from_code, e);
}

static AhcNode *enum_from_code(AhcNode **env) {
  long n = env[0]->u.i;
  AhcNode *c = ahc_mk_con(CONS_TAG, 2);
  c->u.con.fields[0] = ahc_mk_int(n);
  c->u.con.fields[1] = mk_enum_from(n + 1);
  return c;
}

static AhcNode *p_enum_from(AhcNode *a) {
  return mk_enum_from(ahc_eval(a)->u.i);
}

/* Stepped enumerations (Report 3.10 / 6.3.4). enumFromThen is a
   lazy infinite structure with the given stride; enumFromThenTo is
   finite (empty when the stride points away from the bound). */
static AhcNode *enum_ft_code(AhcNode **env);

static AhcNode *mk_enum_ft(long n, long step) {
  AhcNode **e = ahc_env(2);
  e[0] = ahc_mk_int(n);
  e[1] = ahc_mk_int(step);
  return ahc_mk_thunk(enum_ft_code, e);
}

static AhcNode *enum_ft_code(AhcNode **env) {
  long n = env[0]->u.i, step = env[1]->u.i;
  AhcNode *c = ahc_mk_con(CONS_TAG, 2);
  c->u.con.fields[0] = ahc_mk_int(n);
  c->u.con.fields[1] = mk_enum_ft(n + step, step);
  return c;
}

static AhcNode *p_enum_from_then(AhcNode *a, AhcNode *b) {
  long n = ahc_eval(a)->u.i;
  return mk_enum_ft(n, ahc_eval(b)->u.i - n);
}

static AhcNode *p_enum_from_then_to(AhcNode *a, AhcNode *b,
                                    AhcNode *t) {
  long lo = ahc_eval(a)->u.i;
  long step = ahc_eval(b)->u.i - lo;
  long hi = ahc_eval(t)->u.i;
  AhcNode *acc = ahc_mk_con(NIL_TAG, 0);
  long count = 0;
  if (step > 0) count = hi >= lo ? (hi - lo) / step + 1 : 0;
  else if (step < 0) count = hi <= lo ? (lo - hi) / (-step) + 1 : 0;
  else return mk_enum_ft(lo, 0);   /* infinite repeat per Report */
  for (long i = count - 1; i >= 0; i--) {
    AhcNode *cc = ahc_mk_con(CONS_TAG, 2);
    cc->u.con.fields[0] = ahc_mk_int(lo + i * step);
    cc->u.con.fields[1] = acc;
    acc = cc;
  }
  return acc;
}

static AhcNode *p_succ_int(AhcNode *a) {
  return ahc_mk_int(ahc_eval(a)->u.i + 1);
}
static AhcNode *p_pred_int(AhcNode *a) {
  return ahc_mk_int(ahc_eval(a)->u.i - 1);
}

static AhcNode *p_enum_from_to(AhcNode *a, AhcNode *b) {
  long lo = ahc_eval(a)->u.i, hi = ahc_eval(b)->u.i;
  AhcNode *acc = ahc_mk_con(NIL_TAG, 0);
  for (long i = hi; i >= lo; i--) {
    AhcNode *c = ahc_mk_con(CONS_TAG, 2);
    c->u.con.fields[0] = ahc_mk_int(i);
    c->u.con.fields[1] = acc;
    acc = c;
  }
  return acc;
}

/* seq: force the first argument to WHNF, yield the second
   untouched (Report 6.2). The one primitive that makes strictness
   expressible in source - foldl' and ($!) are built on it. */
static AhcNode *p_seq(AhcNode *a, AhcNode *b) {
  ahc_eval(a);
  return b;
}

static AhcNode *p_error(AhcNode *a) {
  AhcNode *cell = ahc_eval(a);
  fflush(stdout);   /* output already produced must precede the die */
  fputs("ahc: error: ", stderr);
  while (cell->tag == AHC_CON && cell->u.con.contag == CONS_TAG) {
    fputc((int)ahc_eval(cell->u.con.fields[0])->u.c, stderr);
    cell = ahc_eval(cell->u.con.fields[1]);
  }
  fputc('\n', stderr);
  exit(1);
}

/* ----- IO: an action is a function World -> result ---------------- */

static AhcNode *the_world;

static void put_list(AhcNode *s, FILE *out) {
  AhcNode *cell = ahc_eval(s);
  while (cell->tag == AHC_CON && cell->u.con.contag == CONS_TAG) {
    fputc((int)ahc_eval(cell->u.con.fields[0])->u.c, out);
    cell = ahc_eval(cell->u.con.fields[1]);
  }
}

/* Function contracts (docs/contracts-design-note.md): force the
 * claim; report and die when it is False; otherwise the wrapped
 * value. Fires when the contracted result is demanded. */
static AhcNode *p_check_claim(AhcNode *b, AhcNode *msg, AhcNode *v) {
  if (ahc_eval(b)->u.con.contag == FALSE_TAG) {
    fflush(stdout);
    fputs("ahc: ", stderr);
    put_list(msg, stderr);
    fputc('\n', stderr);
    exit(1);
  }
  return v;
}

static AhcNode *io_put_str(AhcNode **env, AhcNode *w) {
  (void)w;
  put_list(env[0], stdout);
  return ahc_mk_con(UNIT_TAG, 0);
}

static AhcNode *p_put_str(AhcNode *s) {
  AhcNode **e = ahc_env(1);
  e[0] = s;
  return ahc_mk_fun(io_put_str, e);
}

static AhcNode *io_put_str_ln(AhcNode **env, AhcNode *w) {
  (void)w;
  put_list(env[0], stdout);
  fputc('\n', stdout);
  return ahc_mk_con(UNIT_TAG, 0);
}

static AhcNode *p_put_str_ln(AhcNode *s) {
  AhcNode **e = ahc_env(1);
  e[0] = s;
  return ahc_mk_fun(io_put_str_ln, e);
}

/* bindIO m k = \w -> (k (m w)) w */
static AhcNode *io_bind(AhcNode **env, AhcNode *w) {
  AhcNode *r = ahc_apply(env[0], w);
  return ahc_apply(ahc_apply(env[1], r), w);
}

static AhcNode *p_bind_io(AhcNode *m, AhcNode *k) {
  AhcNode **e = ahc_env(2);
  e[0] = m; e[1] = k;
  return ahc_mk_fun(io_bind, e);
}

/* thenIO m k = \w -> m w `seq-ish` k w */
static AhcNode *io_then(AhcNode **env, AhcNode *w) {
  ahc_eval(ahc_apply(env[0], w));
  return ahc_apply(env[1], w);
}

static AhcNode *p_then_io(AhcNode *m, AhcNode *k) {
  AhcNode **e = ahc_env(2);
  e[0] = m; e[1] = k;
  return ahc_mk_fun(io_then, e);
}

static AhcNode *io_return(AhcNode **env, AhcNode *w) {
  (void)w;
  return env[0];
}

static AhcNode *p_return_io(AhcNode *x) {
  AhcNode **e = ahc_env(1);
  e[0] = x;
  return ahc_mk_fun(io_return, e);
}

AhcNode *ahc_run_io(AhcNode *io) {
  return ahc_eval(ahc_apply(io, the_world));
}

void ahc_run_main(AhcNode *main_io) {
  ahc_eval(ahc_apply(main_io, the_world));
}

/* ----- globals ---------------------------------------------------- */

/* ----- Double arithmetic (Num/Fractional/Show at Double) --------- */

#define DWOP(name, expr)                                              \
  static AhcNode *name(AhcNode *a, AhcNode *b) {                      \
    double x = ahc_eval(a)->u.d, y = ahc_eval(b)->u.d;                \
    (void)x; (void)y;                                                 \
    return (expr);                                                    \
  }

DWOP(p_add_d, ahc_mk_double(x + y))
DWOP(p_sub_d, ahc_mk_double(x - y))
DWOP(p_mul_d, ahc_mk_double(x * y))
DWOP(p_div_d, ahc_mk_double(x / y))

static AhcNode *p_neg_d(AhcNode *a) {
  return ahc_mk_double(-ahc_eval(a)->u.d);
}
static AhcNode *p_abs_d(AhcNode *a) {
  double v = ahc_eval(a)->u.d;
  return ahc_mk_double(v < 0 ? -v : v);
}
static AhcNode *p_signum_d(AhcNode *a) {
  double v = ahc_eval(a)->u.d;
  return ahc_mk_double(v > 0 ? 1.0 : v < 0 ? -1.0 : 0.0);
}
/* Num Double's fromInteger: the argument is an AHC_INT node.
   A bignum beyond 53 bits gets ONE round-to-nearest-even of the
   exact value (top 53 bits, then round/sticky), matching GHC's
   integerToDouble; the naive per-limb accumulation rounds at every
   step and drifts by ulps (fuzzer find, seed 57). */
static AhcNode *p_from_integer_d(AhcNode *a) {
  AhcNode *e = ahc_eval(a);
  if (e->tag == AHC_INT) return ahc_mk_double((double)e->u.i);
  {
    int n = e->u.big.n;
    const uint32_t *d = e->u.big.d;
    int nb = 32 * (n - 1);
    uint32_t top = d[n - 1];
    while (top) { nb++; top >>= 1; }
    if (nb <= 53) {              /* exact: every step representable */
      double v = 0;
      for (int i = n - 1; i >= 0; i--) v = v * 4294967296.0 + d[i];
      return ahc_mk_double(e->u.big.sign < 0 ? -v : v);
    }
    {
      int lo = nb - 53;          /* lowest kept bit */
      uint64_t mant = 0;
      int sticky = 0, round, k;
      for (k = nb - 1; k >= lo; k--)
        mant = (mant << 1) | ((d[k >> 5] >> (k & 31)) & 1u);
      round = (d[(lo - 1) >> 5] >> ((lo - 1) & 31)) & 1u;
      for (k = 0; k < (lo - 1) >> 5 && !sticky; k++)
        if (d[k]) sticky = 1;
      if (!sticky && ((lo - 1) & 31)
          && (d[(lo - 1) >> 5] & ((1u << ((lo - 1) & 31)) - 1u)))
        sticky = 1;
      if (round && (sticky || (mant & 1))) mant++;
      {
        double v = ldexp((double)mant, lo);
        return ahc_mk_double(e->u.big.sign < 0 ? -v : v);
      }
    }
  }
}
/* %.15g round-trips typical values; append .0 when the image has no
   fractional or exponent part, matching Haskell's show for whole
   doubles (show 12.0 = "12.0"). */
static void fmt_double(char *buf, size_t n, double v);

static AhcNode *p_show_d(AhcNode *a) {
  char buf[64];
  fmt_double(buf, sizeof buf, ahc_eval(a)->u.d);
  return ahc_mk_string(buf);
}

/* ----- Data.Bits at Int ------------------------------------------ */

#define BITOP(name, op)                                               \
  static AhcNode *name(AhcNode *a, AhcNode *b) {                      \
    return ahc_mk_int(ahc_eval(a)->u.i op ahc_eval(b)->u.i);          \
  }

BITOP(p_band, &)
BITOP(p_bor, |)
BITOP(p_bxor, ^)
BITOP(p_bshl, <<)
BITOP(p_bshr, >>)

static AhcNode *p_bcompl(AhcNode *a) {
  return ahc_mk_int(~ahc_eval(a)->u.i);
}
static AhcNode *p_popcount(AhcNode *a) {
  return ahc_mk_int(__builtin_popcountl(
    (unsigned long)ahc_eval(a)->u.i));
}

/* ----- Input, arguments, exit ------------------------------------ */

typedef struct { char *p; size_t len, cap; } StrBuf;

static void sb_ch(StrBuf *b, char ch) {
  if (b->len + 1 >= b->cap) {
    b->cap = b->cap ? b->cap * 2 : 64;
    b->p = realloc(b->p, b->cap);
    if (!b->p) ahc_die("out of memory");
  }
  b->p[b->len++] = ch;
}

static void sb_cstr(StrBuf *b, const char *s) {
  while (*s) sb_ch(b, *s++);
}

/* Flatten a Haskell string (evaluated cons spine of chars). */
static void sb_hs(StrBuf *b, AhcNode *s) {
  AhcNode *w = ahc_eval(s);
  while (w->u.con.contag == CONS_TAG) {
    sb_ch(b, (char)ahc_eval(w->u.con.fields[0])->u.c);
    w = ahc_eval(w->u.con.fields[1]);
  }
}

static AhcNode *sb_take(StrBuf *b) {
  AhcNode *r;
  sb_ch(b, 0);
  r = ahc_mk_string(b->p);
  free(b->p);
  return r;
}

char *ahc_marshal_cstring(AhcNode *s) {
  StrBuf b = {0, 0, 0};
  sb_hs(&b, s);
  sb_ch(&b, 0);
  return b.p;
}

void ahc_free_cstring(char *s) {
  free(s);
}

/* ----- wrapper imports: Haskell closures as C function pointers.
   Each wrapper-import site owns a static pool of trampolines and a
   parallel closure-slot array (static data, so the Boehm collector
   sees the closures). The registry maps a trampoline address back
   to its slot so freeHaskellFunPtr can clear it. ---------------- */

#define AHC_MAX_FUNPTRS 1024

static struct { void *tramp; AhcNode **slot; } funptr_reg[AHC_MAX_FUNPTRS];
static int funptr_reg_n = 0;

AhcNode *ahc_wrap_fun(AhcNode *clos, AhcNode **slots, void **tramps,
                      int pool) {
  int i, j, found = 0;
  for (i = 0; i < pool; i++)
    if (!slots[i]) break;
  if (i == pool)
    ahc_die("FFI: wrapper pool exhausted (32 per import site)");
  slots[i] = clos;
  for (j = 0; j < funptr_reg_n; j++)
    if (funptr_reg[j].tramp == tramps[i]) { found = 1; break; }
  if (!found) {
    if (funptr_reg_n == AHC_MAX_FUNPTRS)
      ahc_die("FFI: too many live function pointers");
    funptr_reg[funptr_reg_n].tramp = tramps[i];
    funptr_reg[funptr_reg_n].slot = &slots[i];
    funptr_reg_n++;
  }
  return ahc_mk_ptr(tramps[i]);
}

static AhcNode *io_free_funptr(AhcNode **env, AhcNode *w) {
  AhcNode *p = ahc_eval(env[0]);
  int j;
  (void)w;
  for (j = 0; j < funptr_reg_n; j++)
    if (funptr_reg[j].tramp == p->u.p) {
      *funptr_reg[j].slot = NULL;
      return ahc_mk_con(UNIT_TAG, 0);
    }
  ahc_die("freeHaskellFunPtr: not a wrapper-created FunPtr");
}

static AhcNode *p_free_funptr(AhcNode *p) {
  AhcNode **e = ahc_env(1);
  e[0] = p;
  return ahc_mk_fun(io_free_funptr, e);
}


static int ahc_argc = 0;
static char **ahc_argv = NULL;

void ahc_set_args(int argc, char **argv) {
  ahc_argc = argc;
  ahc_argv = argv;
}

static AhcNode *io_getline(AhcNode **env, AhcNode *w) {
  char *buf = NULL;
  size_t cap = 0, len = 0;
  int ch;
  AhcNode *r;
  (void)env; (void)w;
  while ((ch = fgetc(stdin)) != EOF && ch != '\n') {
    if (len + 2 > cap) {
      cap = cap ? cap * 2 : 64;
      buf = realloc(buf, cap);
      if (!buf) ahc_die("out of memory");
    }
    buf[len++] = (char)ch;
  }
  if (ch == EOF && len == 0)
    ahc_die("Prelude.getLine: end of file");
  if (buf) buf[len] = 0;
  r = ahc_mk_string(buf ? buf : "");
  free(buf);
  return r;
}

static AhcNode *io_iseof(AhcNode **env, AhcNode *w) {
  int ch;
  (void)env; (void)w;
  ch = fgetc(stdin);
  if (ch == EOF)
    return mk_bool(1);
  ungetc(ch, stdin);
  return mk_bool(0);
}

static AhcNode *io_getcontents(AhcNode **env, AhcNode *w) {
  char *buf = NULL;
  size_t cap = 0, len = 0;
  int ch;
  AhcNode *r;
  (void)env; (void)w;
  while ((ch = fgetc(stdin)) != EOF) {
    if (len + 2 > cap) {
      cap = cap ? cap * 2 : 256;
      buf = realloc(buf, cap);
      if (!buf) ahc_die("out of memory");
    }
    buf[len++] = (char)ch;
  }
  if (buf) buf[len] = 0;
  r = ahc_mk_string(buf ? buf : "");
  free(buf);
  return r;
}

static AhcNode *io_readfile(AhcNode **env, AhcNode *w) {
  StrBuf pb = {0, 0, 0};
  FILE *f;
  char *buf = NULL;
  size_t cap = 0, len = 0;
  int ch;
  AhcNode *r;
  (void)w;
  sb_hs(&pb, env[0]);
  sb_ch(&pb, 0);
  f = fopen(pb.p, "r");
  if (!f) {
    fflush(stdout);
    fprintf(stderr, "ahc: %s: openFile: does not exist\n", pb.p);
    exit(1);
  }
  free(pb.p);
  while ((ch = fgetc(f)) != EOF) {
    if (len + 2 > cap) {
      cap = cap ? cap * 2 : 256;
      buf = realloc(buf, cap);
      if (!buf) ahc_die("out of memory");
    }
    buf[len++] = (char)ch;
  }
  fclose(f);
  if (buf) buf[len] = 0;
  r = ahc_mk_string(buf ? buf : "");
  free(buf);
  return r;
}

static AhcNode *p_readfile(AhcNode *path) {
  AhcNode **e = ahc_env(1);
  e[0] = path;
  return ahc_mk_fun(io_readfile, e);
}

/* peekCString :: Ptr Char -> IO String */
static AhcNode *io_peek_cstring(AhcNode **env, AhcNode *w) {
  AhcNode *p = ahc_eval(env[0]);
  (void)w;
  if (p->tag != AHC_PTR || p->u.p == NULL)
    ahc_die("peekCString: NULL pointer");
  return ahc_mk_string((const char *)p->u.p);
}

static AhcNode *p_peek_cstring(AhcNode *p) {
  AhcNode **e = ahc_env(1);
  e[0] = p;
  return ahc_mk_fun(io_peek_cstring, e);
}

/* ----- file handles: an index registry, not raw FILE pointers -
   operations on a closed handle die cleanly instead of touching
   freed memory. Slots 0..2 are the std streams. ---------------- */
#define AHC_MAX_HANDLES 256
static FILE *ahc_handles[AHC_MAX_HANDLES];

static FILE *ahc_handle(long i, const char *what) {
  FILE *f = (i >= 0 && i < AHC_MAX_HANDLES) ? ahc_handles[i] : NULL;
  if (!f) {
    fflush(stdout);
    fprintf(stderr, "ahc: %s: handle is closed\n", what);
    exit(1);
  }
  return f;
}

static AhcNode *io_h_open(AhcNode **env, AhcNode *w) {
  static const char *modes[4] = {"r", "w", "a", "r+"};
  StrBuf pb = {0, 0, 0};
  long m = ahc_eval(env[1])->u.i;
  FILE *f;
  long i;
  (void)w;
  sb_hs(&pb, env[0]);
  sb_ch(&pb, 0);
  if (m < 0 || m > 3) ahc_die("openFile: bad IOMode");
  f = fopen(pb.p, modes[m]);
  if (!f) {
    fflush(stdout);
    fprintf(stderr, "ahc: %s: openFile: %s\n", pb.p,
            m == 0 ? "does not exist" : "cannot open");
    exit(1);
  }
  free(pb.p);
  for (i = 3; i < AHC_MAX_HANDLES && ahc_handles[i]; i++)
    ;
  if (i >= AHC_MAX_HANDLES) ahc_die("openFile: too many open handles");
  ahc_handles[i] = f;
  return ahc_mk_int(i);
}
static AhcNode *p_h_open(AhcNode *path, AhcNode *mode) {
  AhcNode **e = ahc_env(2);
  e[0] = path; e[1] = mode;
  return ahc_mk_fun(io_h_open, e);
}

static AhcNode *io_h_close(AhcNode **env, AhcNode *w) {
  long i = ahc_eval(env[0])->u.i;
  FILE *f = ahc_handle(i, "hClose");
  (void)w;
  if (i > 2) {
    fclose(f);
    ahc_handles[i] = NULL;
  } else
    fflush(f);   /* closing a std stream would break the runtime's
                    own writers; flush instead (documented) */
  return ahc_mk_con(UNIT_TAG, 0);
}
static AhcNode *p_h_close(AhcNode *h) {
  AhcNode **e = ahc_env(1);
  e[0] = h;
  return ahc_mk_fun(io_h_close, e);
}

static AhcNode *io_h_put_str(AhcNode **env, AhcNode *w) {
  FILE *f = ahc_handle(ahc_eval(env[0])->u.i, "hPutStr");
  (void)w;
  put_list(env[1], f);
  return ahc_mk_con(UNIT_TAG, 0);
}
static AhcNode *p_h_put_str(AhcNode *h, AhcNode *s) {
  AhcNode **e = ahc_env(2);
  e[0] = h; e[1] = s;
  return ahc_mk_fun(io_h_put_str, e);
}

static AhcNode *io_h_get_line(AhcNode **env, AhcNode *w) {
  FILE *f = ahc_handle(ahc_eval(env[0])->u.i, "hGetLine");
  char *buf = NULL;
  size_t cap = 0, len = 0;
  int ch;
  AhcNode *r;
  (void)w;
  while ((ch = fgetc(f)) != EOF && ch != '\n') {
    if (len + 2 > cap) {
      cap = cap ? cap * 2 : 64;
      buf = realloc(buf, cap);
      if (!buf) ahc_die("out of memory");
    }
    buf[len++] = (char)ch;
  }
  if (ch == EOF && len == 0)
    ahc_die("hGetLine: end of file");
  if (buf) buf[len] = 0;
  r = ahc_mk_string(buf ? buf : "");
  free(buf);
  return r;
}
static AhcNode *p_h_get_line(AhcNode *h) {
  AhcNode **e = ahc_env(1);
  e[0] = h;
  return ahc_mk_fun(io_h_get_line, e);
}

static AhcNode *io_h_get_char(AhcNode **env, AhcNode *w) {
  FILE *f = ahc_handle(ahc_eval(env[0])->u.i, "hGetChar");
  int ch = fgetc(f);
  (void)w;
  if (ch == EOF) ahc_die("hGetChar: end of file");
  return ahc_mk_char(ch);
}
static AhcNode *p_h_get_char(AhcNode *h) {
  AhcNode **e = ahc_env(1);
  e[0] = h;
  return ahc_mk_fun(io_h_get_char, e);
}

static AhcNode *io_h_get_contents(AhcNode **env, AhcNode *w) {
  FILE *f = ahc_handle(ahc_eval(env[0])->u.i, "hGetContents");
  char *buf = NULL;
  size_t cap = 0, len = 0;
  int ch;
  AhcNode *r;
  (void)w;
  while ((ch = fgetc(f)) != EOF) {
    if (len + 2 > cap) {
      cap = cap ? cap * 2 : 256;
      buf = realloc(buf, cap);
      if (!buf) ahc_die("out of memory");
    }
    buf[len++] = (char)ch;
  }
  if (buf) buf[len] = 0;
  r = ahc_mk_string(buf ? buf : "");
  free(buf);
  return r;
}
static AhcNode *p_h_get_contents(AhcNode *h) {
  AhcNode **e = ahc_env(1);
  e[0] = h;
  return ahc_mk_fun(io_h_get_contents, e);
}

static AhcNode *io_h_is_eof(AhcNode **env, AhcNode *w) {
  FILE *f = ahc_handle(ahc_eval(env[0])->u.i, "hIsEOF");
  int ch = fgetc(f);
  (void)w;
  if (ch == EOF)
    return mk_bool(1);
  ungetc(ch, f);
  return mk_bool(0);
}
static AhcNode *p_h_is_eof(AhcNode *h) {
  AhcNode **e = ahc_env(1);
  e[0] = h;
  return ahc_mk_fun(io_h_is_eof, e);
}

static AhcNode *io_h_flush(AhcNode **env, AhcNode *w) {
  fflush(ahc_handle(ahc_eval(env[0])->u.i, "hFlush"));
  (void)w;
  return ahc_mk_con(UNIT_TAG, 0);
}
static AhcNode *p_h_flush(AhcNode *h) {
  AhcNode **e = ahc_env(1);
  e[0] = h;
  return ahc_mk_fun(io_h_flush, e);
}

static AhcNode *io_getargs(AhcNode **env, AhcNode *w) {
  AhcNode *acc = ahc_mk_con(NIL_TAG, 0);
  (void)env; (void)w;
  for (int i = ahc_argc - 1; i >= 1; i--) {
    AhcNode *cell = ahc_mk_con(CONS_TAG, 2);
    cell->u.con.fields[0] = ahc_mk_string(ahc_argv[i]);
    cell->u.con.fields[1] = acc;
    acc = cell;
  }
  return acc;
}

static AhcNode *io_getprogname(AhcNode **env, AhcNode *w) {
  const char *p = ahc_argc > 0 ? ahc_argv[0] : "ahc";
  const char *base = p;
  (void)env; (void)w;
  for (; *p; p++)
    if (*p == '/') base = p + 1;
  return ahc_mk_string(base);
}

static AhcNode *io_exit_with(AhcNode **env, AhcNode *w) {
  (void)w;
  fflush(stdout);
  exit((int)ahc_eval(env[0])->u.i);
}

static AhcNode *p_exit_with(AhcNode *code) {
  AhcNode **e = ahc_env(1);
  e[0] = code;
  return ahc_mk_fun(io_exit_with, e);
}

/* ----- Floating / RealFrac at Double ----------------------------- */

#define DUOP(name, fn)                                                \
  static AhcNode *name(AhcNode *a) {                                  \
    return ahc_mk_double(fn(ahc_eval(a)->u.d));                       \
  }

DUOP(p_exp_d, exp)
DUOP(p_log_d, log)
DUOP(p_sqrt_d, sqrt)
DUOP(p_sin_d, sin)
DUOP(p_cos_d, cos)
DUOP(p_tan_d, tan)
DUOP(p_asin_d, asin)
DUOP(p_acos_d, acos)
DUOP(p_atan_d, atan)
DUOP(p_sinh_d, sinh)
DUOP(p_cosh_d, cosh)
DUOP(p_tanh_d, tanh)

static AhcNode *p_atan2_d(AhcNode *a, AhcNode *b) {
  return ahc_mk_double(atan2(ahc_eval(a)->u.d, ahc_eval(b)->u.d));
}
static AhcNode *p_isnan_d(AhcNode *a) {
  return mk_bool(isnan(ahc_eval(a)->u.d));
}
static AhcNode *p_isinf_d(AhcNode *a) {
  return mk_bool(isinf(ahc_eval(a)->u.d));
}
static AhcNode *p_isnegzero_d(AhcNode *a) {
  double d = ahc_eval(a)->u.d;
  return mk_bool(d == 0.0 && signbit(d));
}
static AhcNode *p_pow_d(AhcNode *a, AhcNode *b) {
  return ahc_mk_double(pow(ahc_eval(a)->u.d, ahc_eval(b)->u.d));
}
static AhcNode *p_logbase_d(AhcNode *a, AhcNode *b) {
  return ahc_mk_double(log(ahc_eval(b)->u.d) / log(ahc_eval(a)->u.d));
}
static AhcNode *p_floor_d(AhcNode *a) {
  return ahc_mk_int((long)floor(ahc_eval(a)->u.d));
}
static AhcNode *p_ceiling_d(AhcNode *a) {
  return ahc_mk_int((long)ceil(ahc_eval(a)->u.d));
}
/* Report: round is to nearest even (rint under the default rounding
   mode). */
static AhcNode *p_round_d(AhcNode *a) {
  return ahc_mk_int((long)rint(ahc_eval(a)->u.d));
}
static AhcNode *p_truncate_d(AhcNode *a) {
  return ahc_mk_int((long)ahc_eval(a)->u.d);
}
static AhcNode *p_int_to_d(AhcNode *a) {
  return ahc_mk_double((double)ahc_eval(a)->u.i);
}

/* ----- Report 11.4 Show machinery ------------------------------- */

/* Show Char's showList: the whole char list as one quoted, escaped
   string literal - this is how show "abc" becomes "\"abc\"". */
static AhcNode *p_show_string(AhcNode *xs) {
  StrBuf b = {0, 0, 0};
  AhcNode *w = ahc_eval(xs);
  sb_ch(&b, '"');
  while (w->u.con.contag == CONS_TAG) {
    long v = ahc_eval(w->u.con.fields[0])->u.c;
    switch (v) {
    case '"':  sb_cstr(&b, "\\\""); break;
    case '\\': sb_cstr(&b, "\\\\"); break;
    case '\n': sb_cstr(&b, "\\n"); break;
    case '\t': sb_cstr(&b, "\\t"); break;
    case '\r': sb_cstr(&b, "\\r"); break;
    default:
      if (v >= 32 && v <= 126) sb_ch(&b, (char)v);
      else {
        char tmp[16];
        snprintf(tmp, sizeof tmp, "\\%ld", v);
        sb_cstr(&b, tmp);
      }
    }
    w = ahc_eval(w->u.con.fields[1]);
  }
  sb_ch(&b, '"');
  return sb_take(&b);
}

/* Generic showList: "[e1,e2,...]" rendering each element with f. */
static AhcNode *p_shows_list(AhcNode *f, AhcNode *xs) {
  StrBuf b = {0, 0, 0};
  AhcNode *w = ahc_eval(xs);
  int first = 1;
  sb_ch(&b, '[');
  while (w->u.con.contag == CONS_TAG) {
    if (!first) sb_ch(&b, ',');
    first = 0;
    sb_hs(&b, ahc_apply(f, w->u.con.fields[0]));
    w = ahc_eval(w->u.con.fields[1]);
  }
  sb_ch(&b, ']');
  return sb_take(&b);
}

/* showsPrec at Int/Double: negatives are parenthesized when the
   enclosing precedence exceeds 6 (Report 11.4). */
static AhcNode *p_showsprec_int(AhcNode *d, AhcNode *x) {
  long dv = ahc_eval(d)->u.i;
  AhcNode *v = ahc_eval(x);
  int neg = v->tag == AHC_INT ? v->u.i < 0 : v->u.big.sign < 0;
  char *img = big_image(v);
  AhcNode *r;
  if (dv > 6 && neg) {
    size_t l = strlen(img);
    char *p = malloc(l + 3);
    if (!p) ahc_die("out of memory");
    p[0] = '(';
    memcpy(p + 1, img, l);
    p[l + 1] = ')'; p[l + 2] = 0;
    r = ahc_mk_string(p);
    free(p);
  } else {
    r = ahc_mk_string(img);
  }
  free(img);
  return r;
}

/* GHC's show for Double: shortest digit string that round-trips,
   fixed notation when 0.1 <= |v| < 1e7, scientific (d.ddde<exp>)
   otherwise; "Infinity" / "NaN" for the specials. */
/* ----- GHC-exact digit generation --------------------------------
   Burger & Dybvig free-format shortest digits, exactly GHC's
   floatToDigits at base 10. printf's correctly-rounded N-digit
   decimal agrees with this except on last-digit boundary cases
   where two candidates both round-trip - the fuzzer's deep
   campaign found four of them in 10k seeds (M83). All arithmetic
   is exact, over the bignum nodes. */

static int node_cmp_pos(AhcNode *a, AhcNode *b) {
  limb t1[2], t2[2];
  BigView A = big_view(a, t1), B = big_view(b, t2);
  if (A.n != B.n) return A.n < B.n ? -1 : 1;
  return mag_cmp(A.d, A.n, B.d, B.n);
}

static AhcNode *node_mul_small(AhcNode *a, long k) {
  return p_mul(a, ahc_mk_int(k));
}

static AhcNode *node_pow10(int n) {
  AhcNode *r = ahc_mk_int(1);
  int i;
  for (i = 0; i < n; i++) r = node_mul_small(r, 10);
  return r;
}

static AhcNode *node_add_pos(AhcNode *a, AhcNode *b) {
  return p_add(a, b);
}

/* v: positive, finite. digits[] gets '0'+d chars; returns count;
   *k_out = decimal exponent (v ~ 0.d1d2... * 10^k). */
static int bd_digits(double v, char *digits, int *k_out) {
  unsigned long bits;
  unsigned long mant;
  int biased, e, k, nd = 0;
  AhcNode *f, *r, *sN, *mUp, *mDn;
  memcpy(&bits, &v, 8);
  mant = bits & 0xFFFFFFFFFFFFFUL;
  biased = (int)((bits >> 52) & 0x7FF);
  if (biased == 0) {              /* denormal */
    f = ahc_mk_int((long)mant);
    e = -1074;
  } else {
    f = ahc_mk_int((long)(mant | (1UL << 52)));
    e = biased - 1075;
  }
  /* boundaries (Burger-Dybvig, GHC's exact branching; b = 2,
     p = 53, minExp = -1074) */
  {
    int pow2_mant = (biased != 0 && mant == 0);
    if (e >= 0) {
      AhcNode *be = ahc_mk_int(1);
      int i;
      for (i = 0; i < e; i++) be = node_mul_small(be, 2);
      if (!pow2_mant) {
        r = node_mul_small(p_mul(f, be), 2);
        sN = ahc_mk_int(2);
        mUp = be; mDn = be;
      } else {
        r = node_mul_small(node_mul_small(p_mul(f, be), 2), 2);
        sN = ahc_mk_int(4);
        mUp = node_mul_small(be, 2); mDn = be;
      }
    } else {
      /* Asymmetric boundaries ONLY at a binade floor that is not
         the minimum exponent: there the gap below is half the gap
         above. A DENORMAL (e == minExp) has evenly spaced
         neighbours and must take the symmetric case - getting
         this backwards printed one digit too many for values
         below 2^-1022 (fuzzer find, seed 5844). */
      if (e > -1074 && pow2_mant) {
        AhcNode *bk = ahc_mk_int(1);
        int i;
        for (i = 0; i < -e + 1; i++) bk = node_mul_small(bk, 2);
        r = node_mul_small(f, 4);
        sN = node_mul_small(bk, 2);
        mUp = ahc_mk_int(2); mDn = ahc_mk_int(1);
      } else {
        AhcNode *bk = ahc_mk_int(1);
        int i;
        for (i = 0; i < -e; i++) bk = node_mul_small(bk, 2);
        r = node_mul_small(f, 2);
        sN = node_mul_small(bk, 2);
        mUp = ahc_mk_int(1); mDn = ahc_mk_int(1);
      }
    }
  }
  /* k estimate + fixup (GHC's integer log estimate) */
  k = (int)(((long)(52 + e) * 8651L) / 28738L)
      + (((52 + e) < 0) ? 0 : 0);
  if ((52 + e) < 0 && ((long)(52 + e) * 8651L) % 28738L != 0)
    ;   /* C division truncates toward zero; fixup loop corrects */
  for (;;) {
    if (k >= 0) {
      AhcNode *sk = p_mul(sN, node_pow10(k));
      if (node_cmp_pos(node_add_pos(r, mUp), sk) <= 0) break;
      k++;
    } else {
      AhcNode *lhs =
        p_mul(node_pow10(-k), node_add_pos(r, mUp));
      if (node_cmp_pos(lhs, sN) <= 0) break;
      k++;
    }
  }
  for (;;) {          /* also correct a too-high estimate */
    if (k > 0) {
      AhcNode *sk = p_mul(sN, node_pow10(k - 1));
      if (node_cmp_pos(node_add_pos(r, mUp), sk) > 0) break;
      k--;
    } else {
      AhcNode *lhs =
        p_mul(node_pow10(-(k - 1)), node_add_pos(r, mUp));
      if (node_cmp_pos(lhs, sN) > 0) break;
      k--;
    }
  }
  /* scale */
  if (k >= 0) sN = p_mul(sN, node_pow10(k));
  else {
    AhcNode *bk = node_pow10(-k);
    r = p_mul(r, bk);
    mUp = p_mul(mUp, bk);
    mDn = p_mul(mDn, bk);
  }
  /* digit loop */
  for (;;) {
    AhcNode *q, *rem;
    long dn;
    int low, high;
    big_quotrem(node_mul_small(r, 10), sN, &q, &rem);
    dn = ahc_eval(q)->u.i;      /* 0..10, always small */
    r = rem;
    mUp = node_mul_small(mUp, 10);
    mDn = node_mul_small(mDn, 10);
    low = node_cmp_pos(r, mDn) < 0;
    high = node_cmp_pos(node_add_pos(r, mUp), sN) > 0;
    if (!low && !high) {
      digits[nd++] = (char)('0' + dn);
      if (nd > 20) break;       /* cannot happen; safety */
      continue;
    }
    if (low && !high) digits[nd++] = (char)('0' + dn);
    else if (!low && high) digits[nd++] = (char)('0' + dn + 1);
    else {
      if (node_cmp_pos(node_mul_small(r, 2), sN) < 0)
        digits[nd++] = (char)('0' + dn);
      else
        digits[nd++] = (char)('0' + dn + 1);
    }
    break;
  }
  digits[nd] = 0;
  *k_out = k;
  return nd;
}

static void fmt_double(char *buf, size_t n, double v) {
  char sci[64], digits[32];
  int prec, e10, nd, i, j;
  if (isnan(v)) { snprintf(buf, n, "NaN"); return; }
  if (isinf(v)) {
    snprintf(buf, n, v < 0 ? "-Infinity" : "Infinity");
    return;
  }
  if (v == 0.0) {   /* -0.0 == 0.0, but GHC shows the sign */
    snprintf(buf, n, signbit(v) ? "-0.0" : "0.0");
    return;
  }
  (void)sci; (void)prec;
  {
    int k;
    nd = bd_digits(v < 0 ? -v : v, digits, &k);
    e10 = k - 1;    /* 0.d1.. * 10^k  ==  d1.d2.. * 10^(k-1) */
  }
  j = 0;
  if (v < 0) buf[j++] = '-';
  if (e10 >= 0 && e10 < 7) {
    /* fixed: e10+1 integer digits */
    for (i = 0; i <= e10; i++)
      buf[j++] = i < nd ? digits[i] : '0';
    buf[j++] = '.';
    if (e10 + 1 < nd)
      for (i = e10 + 1; i < nd; i++) buf[j++] = digits[i];
    else buf[j++] = '0';
    buf[j] = 0;
  } else if (e10 < 0) {
    /* GHC keeps fixed form down to 0.1 only */
    if (e10 == -1) {
      buf[j++] = '0'; buf[j++] = '.';
      for (i = 0; i < nd; i++) buf[j++] = digits[i];
      buf[j] = 0;
    } else {
      j += snprintf(buf + j, n - j, "%c.%se%d", digits[0],
                    nd > 1 ? digits + 1 : "0", e10);
    }
  } else {
    j += snprintf(buf + j, n - j, "%c.%se%d", digits[0],
                  nd > 1 ? digits + 1 : "0", e10);
  }
}

static AhcNode *p_showsprec_d(AhcNode *d, AhcNode *x) {
  long dv = ahc_eval(d)->u.i;
  double v = ahc_eval(x)->u.d;
  char num[48], out[52];
  fmt_double(num, sizeof num, v);
  if (dv > 6 && num[0] == '-')   /* covers -0.0 and -Infinity */
    snprintf(out, sizeof out, "(%s)", num);
  else snprintf(out, sizeof out, "%s", num);
  return ahc_mk_string(out);
}

/* Refinement-types extension, stage 4: Double range check. */
static AhcNode *p_check_range_d(AhcNode *lo, AhcNode *hi, AhcNode *x) {
  double l = ahc_eval(lo)->u.d;
  double h = ahc_eval(hi)->u.d;
  AhcNode *v = ahc_eval(x);
  if (v->u.d < l || v->u.d > h) {
    fflush(stdout);
    fprintf(stderr, "refinement violation: %g not in %g .. %g\n",
            v->u.d, l, h);
    exit(1);
  }
  return v;
}

/* Refinement-types extension, stage 3: modular normalization. Not a
   contract - values crossing an `Int mod N` boundary wrap into
   [0, N) with mathematical mod (result is never negative). */
static AhcNode *p_wrap_mod(AhcNode *n, AhcNode *x) {
  long m = ahc_eval(n)->u.i;
  AhcNode *e = ahc_eval(x);
  if (e->tag == AHC_INT)
    return ahc_mk_int(((e->u.i % m) + m) % m);
  {
    limb *w = limb_alloc(e->u.big.n);
    long r;
    for (int i = 0; i < e->u.big.n; i++) w[i] = e->u.big.d[i];
    r = (long)mag_divmod_small(w, e->u.big.n, (limb)m);
    if (e->u.big.sign < 0) r = -r;
    return ahc_mk_int(((r % m) + m) % m);
  }
}

/* Refinement-types extension, stage 2: lazily-fired predicate check.
   p is the compiled `$pred :: BASE -> Bool` global; fires like the
   range check, when the refined value is first demanded. */
static AhcNode *p_check_pred(AhcNode *p, AhcNode *x) {
  AhcNode *v = ahc_eval(x);
  AhcNode *r = ahc_eval(ahc_apply(p, v));
  if (r->u.con.contag == FALSE_TAG) {
    fflush(stdout);
    if (v->tag == AHC_INT)
      fprintf(stderr, "refinement violation: predicate rejected %ld\n",
              v->u.i);
    else if (v->tag == AHC_CHAR)
      fprintf(stderr,
              "refinement violation: predicate rejected '%c'\n",
              (char)v->u.c);
    else
      fprintf(stderr,
              "refinement violation: predicate rejected the value\n");
    exit(1);
  }
  return v;
}

/* Refinement-types extension: lazily-fired range check. Strict in
   the checked value; the check application itself is a thunk, so the
   check fires exactly when the refined value is first demanded. */
static long long_clamp(AhcNode *e) {
  if (e->tag == AHC_INT) return e->u.i;
  return e->u.big.sign < 0 ? LONG_MIN : LONG_MAX;
}

static AhcNode *p_check_range(AhcNode *lo, AhcNode *hi, AhcNode *x) {
  long l = ahc_eval(lo)->u.i;
  long h = ahc_eval(hi)->u.i;
  AhcNode *ev = ahc_eval(x);
  AhcNode *v = ev->tag == AHC_BIGINT
                 ? ahc_mk_int(long_clamp(ev)) : ev;
  if (v->u.i < l || v->u.i > h) {
    fflush(stdout);
    fprintf(stderr, "refinement violation: %ld not in %ld .. %ld\n",
            v->u.i, l, h);
    exit(1);
  }
  return v;
}

AhcNode *ahc_prim_add_int, *ahc_prim_sub_int, *ahc_prim_mul_int,
  *ahc_prim_neg_int, *ahc_prim_abs_int, *ahc_prim_signum_int,
  *ahc_prim_div_int, *ahc_prim_mod_int, *ahc_prim_quot_int,
  *ahc_prim_rem_int,
  *ahc_prim_eq_int, *ahc_prim_ne_int, *ahc_prim_lt_int,
  *ahc_prim_le_int, *ahc_prim_gt_int, *ahc_prim_ge_int,
  *ahc_prim_eq_char, *ahc_prim_lt_char,
  *ahc_prim_eq_poly, *ahc_prim_compare_poly,
  *ahc_prim_enum_from_int,
  *ahc_prim_show_int, *ahc_prim_show_char, *ahc_prim_show_bool,
  *ahc_prim_from_integer,
  *ahc_prim_enum_from_to_int,
  *ahc_prim_put_str, *ahc_prim_put_str_ln,
  *ahc_prim_bind_io, *ahc_prim_then_io, *ahc_prim_return_io,
  *ahc_prim_error, *ahc_prim_seq, *ahc_prim_from_rational_d,
  *ahc_prim_ord, *ahc_prim_chr,
  *ahc_prim_band, *ahc_prim_bor, *ahc_prim_bxor,
  *ahc_prim_bshl, *ahc_prim_bshr, *ahc_prim_bcompl,
  *ahc_prim_popcount,
  *ahc_prim_getline, *ahc_prim_getcontents, *ahc_prim_readfile,
  *ahc_prim_h_open, *ahc_prim_h_close, *ahc_prim_h_put_str,
  *ahc_prim_h_get_line, *ahc_prim_h_get_char,
  *ahc_prim_h_get_contents, *ahc_prim_h_is_eof, *ahc_prim_h_flush,
  *ahc_prim_getargs, *ahc_prim_getprogname, *ahc_prim_exit_with,
  *ahc_prim_iseof,
  *ahc_prim_exp_d, *ahc_prim_log_d, *ahc_prim_sqrt_d,
  *ahc_prim_pow_d, *ahc_prim_logbase_d,
  *ahc_prim_atan2_d,
  *ahc_prim_isnan_d, *ahc_prim_isinf_d, *ahc_prim_isnegzero_d,
  *ahc_prim_sin_d, *ahc_prim_cos_d, *ahc_prim_tan_d,
  *ahc_prim_asin_d, *ahc_prim_acos_d, *ahc_prim_atan_d,
  *ahc_prim_sinh_d, *ahc_prim_cosh_d, *ahc_prim_tanh_d,
  *ahc_prim_floor_d, *ahc_prim_ceiling_d, *ahc_prim_round_d,
  *ahc_prim_truncate_d, *ahc_prim_int_to_d,
  *ahc_prim_enum_from_then, *ahc_prim_enum_from_then_to,
  *ahc_prim_succ_int, *ahc_prim_pred_int,
  *ahc_prim_show_string, *ahc_prim_shows_list,
  *ahc_prim_showsprec_int, *ahc_prim_showsprec_d,
  *ahc_prim_check_range, *ahc_prim_check_pred, *ahc_prim_wrap_mod,
  *ahc_prim_check_claim,
  *ahc_prim_check_range_d,
  *ahc_prim_add_d, *ahc_prim_sub_d, *ahc_prim_mul_d, *ahc_prim_div_d,
  *ahc_prim_neg_d, *ahc_prim_abs_d, *ahc_prim_signum_d,
  *ahc_prim_from_integer_d, *ahc_prim_show_d,
  *ahc_prim_null_ptr, *ahc_prim_peek_cstring,
  *ahc_prim_free_funptr;

void ahc_rts_init(void) {
#ifdef AHC_USE_BOEHM
  GC_INIT();
#endif
  the_world = ahc_mk_con(UNIT_TAG, 0);
  ahc_prim_add_int = mk_prim2(p_add);
  ahc_prim_sub_int = mk_prim2(p_sub);
  ahc_prim_mul_int = mk_prim2(p_mul);
  ahc_prim_div_int = mk_prim2(p_div);
  ahc_prim_mod_int = mk_prim2(p_mod);
  ahc_prim_quot_int = mk_prim2(p_quot);
  ahc_prim_rem_int = mk_prim2(p_rem);
  ahc_prim_eq_int = mk_prim2(p_eq);
  ahc_prim_ne_int = mk_prim2(p_ne);
  ahc_prim_lt_int = mk_prim2(p_lt);
  ahc_prim_le_int = mk_prim2(p_le);
  ahc_prim_gt_int = mk_prim2(p_gt);
  ahc_prim_ge_int = mk_prim2(p_ge);
  ahc_prim_eq_char = mk_prim2(p_eq_char);
  ahc_prim_lt_char = mk_prim2(p_lt_char);
  ahc_prim_neg_int = mk_prim1(p_neg);
  ahc_prim_abs_int = mk_prim1(p_abs);
  ahc_prim_signum_int = mk_prim1(p_signum);
  ahc_prim_from_integer = mk_prim1(p_from_integer);
  ahc_prim_show_int = mk_prim1(p_show_int);
  ahc_prim_show_char = mk_prim1(p_show_char);
  ahc_prim_show_bool = mk_prim1(p_show_bool);
  ahc_prim_enum_from_to_int = mk_prim2(p_enum_from_to);
  ahc_prim_enum_from_int = mk_prim1(p_enum_from);
  ahc_prim_enum_from_then = mk_prim2(p_enum_from_then);
  ahc_prim_enum_from_then_to = mk_prim3(p_enum_from_then_to);
  ahc_prim_succ_int = mk_prim1(p_succ_int);
  ahc_prim_pred_int = mk_prim1(p_pred_int);
  ahc_prim_eq_poly = mk_prim2(p_eq_poly);
  ahc_prim_compare_poly = mk_prim2(p_compare_poly);
  ahc_prim_put_str = mk_prim1(p_put_str);
  ahc_prim_put_str_ln = mk_prim1(p_put_str_ln);
  ahc_prim_bind_io = mk_prim2(p_bind_io);
  ahc_prim_then_io = mk_prim2(p_then_io);
  ahc_prim_return_io = mk_prim1(p_return_io);
  ahc_prim_error = mk_prim1(p_error);
  ahc_prim_seq = mk_prim2(p_seq);
  ahc_prim_from_rational_d = mk_prim1(p_from_rational_d);
  ahc_prim_ord = mk_prim1(p_ord);
  ahc_prim_chr = mk_prim1(p_chr);
  ahc_prim_check_range = mk_prim3(p_check_range);
  ahc_prim_check_pred = mk_prim2(p_check_pred);
  ahc_prim_check_claim = mk_prim3(p_check_claim);
  ahc_prim_wrap_mod = mk_prim2(p_wrap_mod);
  ahc_prim_band = mk_prim2(p_band);
  ahc_prim_bor = mk_prim2(p_bor);
  ahc_prim_bxor = mk_prim2(p_bxor);
  ahc_prim_bshl = mk_prim2(p_bshl);
  ahc_prim_bshr = mk_prim2(p_bshr);
  ahc_prim_bcompl = mk_prim1(p_bcompl);
  ahc_prim_popcount = mk_prim1(p_popcount);
  ahc_handles[0] = stdin;
  ahc_handles[1] = stdout;
  ahc_handles[2] = stderr;
  ahc_prim_h_open = mk_prim2(p_h_open);
  ahc_prim_h_close = mk_prim1(p_h_close);
  ahc_prim_h_put_str = mk_prim2(p_h_put_str);
  ahc_prim_h_get_line = mk_prim1(p_h_get_line);
  ahc_prim_h_get_char = mk_prim1(p_h_get_char);
  ahc_prim_h_get_contents = mk_prim1(p_h_get_contents);
  ahc_prim_h_is_eof = mk_prim1(p_h_is_eof);
  ahc_prim_h_flush = mk_prim1(p_h_flush);
  ahc_prim_getline = ahc_mk_fun(io_getline, NULL);
  ahc_prim_iseof = ahc_mk_fun(io_iseof, NULL);
  ahc_prim_getcontents = ahc_mk_fun(io_getcontents, NULL);
  ahc_prim_readfile = mk_prim1(p_readfile);
  ahc_prim_getargs = ahc_mk_fun(io_getargs, NULL);
  ahc_prim_getprogname = ahc_mk_fun(io_getprogname, NULL);
  ahc_prim_exit_with = mk_prim1(p_exit_with);
  ahc_prim_exp_d = mk_prim1(p_exp_d);
  ahc_prim_log_d = mk_prim1(p_log_d);
  ahc_prim_sqrt_d = mk_prim1(p_sqrt_d);
  ahc_prim_pow_d = mk_prim2(p_pow_d);
  ahc_prim_logbase_d = mk_prim2(p_logbase_d);
  ahc_prim_sin_d = mk_prim1(p_sin_d);
  ahc_prim_cos_d = mk_prim1(p_cos_d);
  ahc_prim_tan_d = mk_prim1(p_tan_d);
  ahc_prim_asin_d = mk_prim1(p_asin_d);
  ahc_prim_acos_d = mk_prim1(p_acos_d);
  ahc_prim_atan_d = mk_prim1(p_atan_d);
  ahc_prim_atan2_d = mk_prim2(p_atan2_d);
  ahc_prim_isnan_d = mk_prim1(p_isnan_d);
  ahc_prim_isinf_d = mk_prim1(p_isinf_d);
  ahc_prim_isnegzero_d = mk_prim1(p_isnegzero_d);
  ahc_prim_sinh_d = mk_prim1(p_sinh_d);
  ahc_prim_cosh_d = mk_prim1(p_cosh_d);
  ahc_prim_tanh_d = mk_prim1(p_tanh_d);
  ahc_prim_floor_d = mk_prim1(p_floor_d);
  ahc_prim_ceiling_d = mk_prim1(p_ceiling_d);
  ahc_prim_round_d = mk_prim1(p_round_d);
  ahc_prim_truncate_d = mk_prim1(p_truncate_d);
  ahc_prim_int_to_d = mk_prim1(p_int_to_d);
  ahc_prim_show_string = mk_prim1(p_show_string);
  ahc_prim_shows_list = mk_prim2(p_shows_list);
  ahc_prim_showsprec_int = mk_prim2(p_showsprec_int);
  ahc_prim_showsprec_d = mk_prim2(p_showsprec_d);
  ahc_prim_check_range_d = mk_prim3(p_check_range_d);
  ahc_prim_add_d = mk_prim2(p_add_d);
  ahc_prim_sub_d = mk_prim2(p_sub_d);
  ahc_prim_mul_d = mk_prim2(p_mul_d);
  ahc_prim_div_d = mk_prim2(p_div_d);
  ahc_prim_neg_d = mk_prim1(p_neg_d);
  ahc_prim_abs_d = mk_prim1(p_abs_d);
  ahc_prim_signum_d = mk_prim1(p_signum_d);
  ahc_prim_from_integer_d = mk_prim1(p_from_integer_d);
  ahc_prim_show_d = mk_prim1(p_show_d);
  ahc_prim_null_ptr = ahc_mk_ptr(NULL);
  ahc_prim_peek_cstring = mk_prim1(p_peek_cstring);
  ahc_prim_free_funptr = mk_prim1(p_free_funptr);
}
