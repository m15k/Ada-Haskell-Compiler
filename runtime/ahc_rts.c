#include "ahc_rts.h"
#include <stdio.h>
#include <stdlib.h>
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

#define IWOP(name, expr)                                              \
  static AhcNode *name(AhcNode *a, AhcNode *b) {                      \
    long x = ahc_eval(a)->u.i, y = ahc_eval(b)->u.i;                  \
    (void)x; (void)y;                                                 \
    return (expr);                                                    \
  }

IWOP(p_add, ahc_mk_int(x + y))
IWOP(p_sub, ahc_mk_int(x - y))
IWOP(p_mul, ahc_mk_int(x * y))
IWOP(p_div, y == 0 ? (ahc_die("divide by zero"), (AhcNode *)0)
                   : ahc_mk_int((x % y != 0 && ((x < 0) != (y < 0)))
                                  ? x / y - 1 : x / y))
IWOP(p_mod, y == 0 ? (ahc_die("divide by zero"), (AhcNode *)0)
                   : ahc_mk_int(((x % y) + y) % y))
IWOP(p_quot, y == 0 ? (ahc_die("divide by zero"), (AhcNode *)0)
                    : ahc_mk_int(x / y))
IWOP(p_rem, y == 0 ? (ahc_die("divide by zero"), (AhcNode *)0)
                   : ahc_mk_int(x % y))
IWOP(p_eq, mk_bool(x == y))
IWOP(p_ne, mk_bool(x != y))
IWOP(p_lt, mk_bool(x < y))
IWOP(p_le, mk_bool(x <= y))
IWOP(p_gt, mk_bool(x > y))
IWOP(p_ge, mk_bool(x >= y))

static AhcNode *p_neg(AhcNode *a) { return ahc_mk_int(-ahc_eval(a)->u.i); }
static AhcNode *p_abs(AhcNode *a) {
  long x = ahc_eval(a)->u.i; return ahc_mk_int(x < 0 ? -x : x);
}
static AhcNode *p_signum(AhcNode *a) {
  long x = ahc_eval(a)->u.i;
  return ahc_mk_int(x > 0 ? 1 : (x < 0 ? -1 : 0));
}
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
  char buf[32];
  snprintf(buf, sizeof buf, "%ld", ahc_eval(a)->u.i);
  return ahc_mk_string(buf);
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

static AhcNode *p_error(AhcNode *a) {
  AhcNode *cell = ahc_eval(a);
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
/* Num Double's fromInteger: the argument is an AHC_INT node. */
static AhcNode *p_from_integer_d(AhcNode *a) {
  return ahc_mk_double((double)ahc_eval(a)->u.i);
}
/* %.15g round-trips typical values; append .0 when the image has no
   fractional or exponent part, matching Haskell's show for whole
   doubles (show 12.0 = "12.0"). */
static AhcNode *p_show_d(AhcNode *a) {
  char buf[48];
  int has_mark = 0;
  size_t i;
  snprintf(buf, sizeof buf - 3, "%.15g", ahc_eval(a)->u.d);
  for (i = 0; buf[i]; i++)
    if (buf[i] == '.' || buf[i] == 'e' || buf[i] == 'n' ||
        buf[i] == 'f')
      has_mark = 1;
  if (!has_mark) { buf[i] = '.'; buf[i + 1] = '0'; buf[i + 2] = 0; }
  return ahc_mk_string(buf);
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
  long v = ahc_eval(x)->u.i;
  return ahc_mk_int(((v % m) + m) % m);
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
static AhcNode *p_check_range(AhcNode *lo, AhcNode *hi, AhcNode *x) {
  long l = ahc_eval(lo)->u.i;
  long h = ahc_eval(hi)->u.i;
  AhcNode *v = ahc_eval(x);
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
  *ahc_prim_error, *ahc_prim_ord, *ahc_prim_chr,
  *ahc_prim_check_range, *ahc_prim_check_pred, *ahc_prim_wrap_mod,
  *ahc_prim_check_range_d,
  *ahc_prim_add_d, *ahc_prim_sub_d, *ahc_prim_mul_d, *ahc_prim_div_d,
  *ahc_prim_neg_d, *ahc_prim_abs_d, *ahc_prim_signum_d,
  *ahc_prim_from_integer_d, *ahc_prim_show_d;

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
  ahc_prim_eq_poly = mk_prim2(p_eq_poly);
  ahc_prim_compare_poly = mk_prim2(p_compare_poly);
  ahc_prim_put_str = mk_prim1(p_put_str);
  ahc_prim_put_str_ln = mk_prim1(p_put_str_ln);
  ahc_prim_bind_io = mk_prim2(p_bind_io);
  ahc_prim_then_io = mk_prim2(p_then_io);
  ahc_prim_return_io = mk_prim1(p_return_io);
  ahc_prim_error = mk_prim1(p_error);
  ahc_prim_ord = mk_prim1(p_ord);
  ahc_prim_chr = mk_prim1(p_chr);
  ahc_prim_check_range = mk_prim3(p_check_range);
  ahc_prim_check_pred = mk_prim2(p_check_pred);
  ahc_prim_wrap_mod = mk_prim2(p_wrap_mod);
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
}
