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
#include <setjmp.h>

typedef enum {
  AHC_THUNK, AHC_BLACKHOLE, AHC_FUN, AHC_CON, AHC_IND,
  AHC_INT, AHC_DOUBLE, AHC_CHAR, AHC_BIGINT, AHC_PTR,
  AHC_CLAIM,  /* transient: tag claimed, owner not yet published */
  AHC_BYTES   /* packed byte slice (Text): always-WHNF, immutable */
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
    struct { void *owner; void *waiters; } bh;  /* AHC_BLACKHOLE */
    long i;
    double d;
    long c;
    struct { int32_t sign; int32_t n; uint32_t *d; } big;
    /* byte slice into a shared immutable payload (valid UTF-8 by
       construction); off/len make take/drop O(1) shares */
    struct { int32_t len; int32_t off; uint8_t *b; } bytes;
    void *p;
  } u;
};

AhcNode *ahc_eval(AhcNode *n);                 /* to WHNF, updating   */
AhcNode *ahc_apply(AhcNode *f, AhcNode *a);    /* general application */

AhcNode **ahc_env(int n);                      /* allocate env array  */
AhcNode *ahc_mk_thunk(AhcCode code, AhcNode **env);
AhcNode *ahc_mk_fun(AhcFn fn, AhcNode **env);
AhcNode *ahc_mk_int(long v);
AhcNode *ahc_mk_ulong(unsigned long v);        /* bignum > LONG_MAX */
AhcNode *ahc_mk_big_str(const char *lexeme);   /* literal > long */
AhcNode *ahc_mk_ratlit(long contag, const char *n, const char *d);
void ahc_set_args(int argc, char **argv);      /* called by main() */
AhcNode *ahc_mk_double(double v);
AhcNode *ahc_mk_char(long v);
AhcNode *ahc_mk_con(int contag, int arity);    /* fields set after    */
AhcNode *ahc_mk_confun(int contag, int arity); /* curried worker      */
AhcNode *ahc_mk_selector(int index);           /* dict field access   */
AhcNode *ahc_mk_string(const char *s);         /* to [Char]           */
AhcNode *ahc_mk_string_len(const char *s, size_t len); /* NUL-safe    */
AhcNode *ahc_mk_bytes(const uint8_t *src, int32_t len); /* copies     */
AhcNode *ahc_mk_bytes_slice(AhcNode *t, int32_t off, int32_t len);
AhcNode *ahc_mk_missing(const char *what);     /* dies when forced    */
AhcNode *ahc_mk_ptr(void *p);                  /* foreign pointer     */

/* FFI support: a curried prim of any arity (args arrive as possibly
   unevaluated nodes), and Haskell-string -> malloc'd NUL-terminated
   C string (caller frees). */
typedef AhcNode *(*AhcPrimN)(AhcNode **args);
AhcNode *ahc_mk_primn(int arity, AhcPrimN f);
char *ahc_marshal_cstring(AhcNode *s);
void ahc_free_cstring(char *s);

/* Wrapper imports: claim a slot in the site's trampoline pool for
   the closure and return the matching C function pointer node. */
AhcNode *ahc_wrap_fun(AhcNode *clos, AhcNode **slots, void **tramps,
                      int pool);

void ahc_run_main(AhcNode *main_io);           /* execute IO action   */
AhcNode *ahc_run_io(AhcNode *io);              /* run IO, return node */

/* Boundary error protocol (foreign-export entry functions): the
   entry does `if (setjmp(*ahc_err_frame())) return 0;`, evaluates,
   then ahc_err_disarm() before returning. A runtime error inside
   the armed region lands in ahc_last_error() ("" = no error). */
jmp_buf *ahc_err_frame(void);
void ahc_err_disarm(void);
const char *ahc_last_error(void);
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
  *ahc_prim_error, *ahc_prim_seq, *ahc_prim_from_rational_d,
  *ahc_prim_scope, *ahc_prim_spawn, *ahc_prim_await,
  *ahc_prim_chan_new, *ahc_prim_chan_send, *ahc_prim_chan_recv,
  *ahc_prim_task_yield,
  *ahc_prim_wait_read, *ahc_prim_wait_write, *ahc_prim_try_recv,
  *ahc_prim_select_recv, *ahc_prim_wait_read_or,
  *ahc_prim_prot_new, *ahc_prim_prot_read,
  *ahc_prim_prot_update, *ahc_prim_prot_entry,
  *ahc_prim_par, *ahc_prim_pseq,
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
  *ahc_prim_free_funptr,
  *ahc_prim_malloc_bytes, *ahc_prim_free_ptr,
  *ahc_prim_plus_ptr, *ahc_prim_cast_ptr,
  *ahc_prim_peek_i8, *ahc_prim_peek_i16, *ahc_prim_peek_i32,
  *ahc_prim_peek_i64, *ahc_prim_peek_u8, *ahc_prim_peek_u16,
  *ahc_prim_peek_u32, *ahc_prim_peek_u64,
  *ahc_prim_peek_d, *ahc_prim_peek_p,
  *ahc_prim_poke_i8, *ahc_prim_poke_i16, *ahc_prim_poke_i32,
  *ahc_prim_poke_i64, *ahc_prim_poke_u8, *ahc_prim_poke_u16,
  *ahc_prim_poke_u32, *ahc_prim_poke_u64,
  *ahc_prim_poke_d, *ahc_prim_poke_p,
  *ahc_prim_new_cstring, *ahc_prim_peek_cstring_len,
  *ahc_prim_text_pack, *ahc_prim_text_unpack, *ahc_prim_text_append,
  *ahc_prim_text_length, *ahc_prim_text_byte_length,
  *ahc_prim_text_index, *ahc_prim_text_take, *ahc_prim_text_drop,
  *ahc_prim_text_show;

void ahc_rts_init(void);

#endif
