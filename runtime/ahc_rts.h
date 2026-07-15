/* AHC runtime (Phase 3, PRD Epic 3): call-by-need graph reduction.
 *
 * Every value is a heap Node. Thunks are updated in place (via an
 * indirection) after their first evaluation - laziness with sharing.
 * Functions are curried one-argument closures; constructors are
 * collected by a generic worker until saturated. Allocation goes
 * through the Boehm-Demers-Weiser conservative collector when built
 * with -DAHC_USE_BOEHM (the PRD's GC strategy), plain malloc otherwise.
 *
 * Constructor tags mirror AHC.Core DataCon_Info.Tag (1-based):
 * Bool: False=1 True=2; lists: []=1 (:)=2; (): ()=1.
 */
#ifndef AHC_RTS_H
#define AHC_RTS_H

#include <stdint.h>
#include <stddef.h>

typedef enum {
  AHC_THUNK, AHC_BLACKHOLE, AHC_FUN, AHC_CON, AHC_IND,
  AHC_INT, AHC_DOUBLE, AHC_CHAR
} AhcTag;

typedef struct AhcNode AhcNode;
typedef AhcNode *(*AhcCode)(AhcNode **env);            /* thunk entry */
typedef AhcNode *(*AhcFn)(AhcNode **env, AhcNode *arg); /* 1-arg fn  */

struct AhcNode {
  AhcTag tag;
  union {
    struct { AhcCode code; AhcNode **env; } thunk;
    struct { AhcFn fn; AhcNode **env; } fun;
    struct { int contag; int arity; AhcNode **fields; } con;
    AhcNode *ind;
    long i;
    double d;
    long c;
  } u;
};

AhcNode *ahc_eval(AhcNode *n);                 /* to WHNF, updating   */
AhcNode *ahc_apply(AhcNode *f, AhcNode *a);    /* general application */

AhcNode **ahc_env(int n);                      /* allocate env array  */
AhcNode *ahc_mk_thunk(AhcCode code, AhcNode **env);
AhcNode *ahc_mk_fun(AhcFn fn, AhcNode **env);
AhcNode *ahc_mk_int(long v);
AhcNode *ahc_mk_double(double v);
AhcNode *ahc_mk_char(long v);
AhcNode *ahc_mk_con(int contag, int arity);    /* fields set after    */
AhcNode *ahc_mk_confun(int contag, int arity); /* curried worker      */
AhcNode *ahc_mk_selector(int index);           /* dict field access   */
AhcNode *ahc_mk_string(const char *s);         /* to [Char]           */
AhcNode *ahc_mk_missing(const char *what);     /* dies when forced    */

void ahc_run_main(AhcNode *main_io);           /* execute IO action   */
void ahc_die(const char *msg) __attribute__((noreturn));

/* Wired primitives (globals initialized by ahc_rts_init). */
extern AhcNode *ahc_prim_add_int, *ahc_prim_sub_int, *ahc_prim_mul_int,
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
  *ahc_prim_error, *ahc_prim_ord, *ahc_prim_chr;

void ahc_rts_init(void);

#endif
