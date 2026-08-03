/* _XOPEN_SOURCE must predate EVERY include: Darwin's ucontext_t
   only carries its inline register block (__mcontext_data) when the
   macro is visible the first time sys/ucontext.h is seen, and the
   stub layout is 56 bytes where the real one is 768 - getcontext
   against the stub corrupts whatever follows it. (Found the hard
   way: wild jumps into green-thread stacks.) */
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE 600
#endif
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE 1    /* _XOPEN_SOURCE alone hides MAP_ANON */
#endif
#include <ucontext.h>
#include <poll.h>

#if defined(AHC_GC_OWN) && !defined(__APPLE__)
/* The own collector reads thread stack bounds with
   pthread_get_stackaddr_np and the data segment through dyld. Linux
   equivalents exist (pthread_getattr_np, __data_start/_end) and the
   data-segment half is already written below - but the stack half is
   not, and shipping it untested is how this project acquires bugs.
   Say so plainly rather than failing at an undeclared function. */
#error "AHC_GC=own is macOS-only today; use AHC_GC=boehm or none"
#endif

#include <pthread.h>

#include "ahc_rts.h"
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <math.h>
#include <limits.h>
#include <string.h>

#if defined(AHC_GC_OWN)
/* The collector campaign's own allocator (C1, leak mode -
   docs/collector-design-note.md). Kinds: 0 node, 1 ptr-array,
   2 misc, 3 large. */
static void *own_alloc(int kind, size_t n);
#define AHC_ALLOC(n) own_alloc(2, (n))
#elif defined(AHC_USE_BOEHM)
#include <gc.h>
#define AHC_ALLOC(n) GC_MALLOC(n)
#else
#define AHC_ALLOC(n) malloc(n)
#endif

/* Boundary error recovery: while a foreign-export entry function is
   on the stack (an "armed" frame), a runtime error unwinds to that
   entry and becomes a reported error instead of killing the host
   process. Outside any armed frame - an ordinary AHC program -
   ahc_die exits as it always has. */

#define AHC_ERR_DEPTH 8

/* ----- green threads (Phase A: one OS thread) --------------------
   docs/concurrency-design-note.md. Tasks are ucontext coroutines.
   ONE task runs at a time; the scheduler is a strict FIFO run
   queue whose only scheduling points are the IO bind/then
   boundaries and blocking operations - which is what makes every
   schedule reproducible. Error frames live per task so a spawned
   task's death fails its Task instead of the process.

   Stacks are the 512MB-executable-stack trick generalized per
   green thread: a 64MB VIRTUAL reservation (address space is the
   cheap resource on 64-bit; untouched pages cost nothing) over a
   PROT_NONE guard page, so lazy evaluation gets the same deep
   recursion budget it has on the main stack and an overflow dies
   with a clean message instead of scribbling the heap. The
   collector is told about exactly the LIVE extent [sp, top] of
   every parked stack (GC_add_roots at switch-out, removed at
   switch-in), and GC_set_stackbottom retargets the running one. */

#include <sys/mman.h>
#include <unistd.h>
#include <signal.h>

#define AHC_TASK_STACK (64ul * 1024 * 1024)

typedef struct AhcTask AhcTask;
typedef struct AhcScope AhcScope;

struct AhcTask {
  ucontext_t ctx;
  char *stack;            /* mmap base = the guard page; main: NULL */
  char *stack_top;        /* the cold end the collector scans to */
  char *parked_lo;        /* live-extent low mark while parked */
  int id;
  int state;              /* 0 run, 1 blocked, 2 done, 3 failed */
  int awaited;            /* someone called await: failure is theirs */
  int is_worker;          /* a B1 spark worker's shell, not a green
                             task: never parks, never scheduled */
  AhcNode *action;        /* the IO action a spawned task runs */
  AhcNode *result;
  AhcNode *xfer;          /* channel hand-off mailbox */
  AhcTask *qnext;         /* run-queue / wait-list linkage */
  AhcTask *join_waiters;  /* tasks parked on my completion */
  AhcTask *ionext;        /* fd-wait list linkage (M127); a dual
                             waiter sits in a channel's waiter list
                             via qnext AND here at once */
  int wait_fd;            /* meaningful only while on the io list */
  short wait_ev;          /* POLLIN / POLLOUT */
  long sel_index;         /* which select alternative fired */
  jmp_buf err_stack[AHC_ERR_DEPTH];
  int err_depth;
  char err_msg[512];      /* ahc_last_error; the death message at 3 */
};

struct AhcScope {
  AhcTask **kids;
  int n, cap;
};

static AhcTask main_task;            /* id 0, the process itself */

/* Thread-local: on the main OS thread this walks the green tasks
   as they switch; on a B1 spark worker it stays pinned to that
   worker's shell. Everything scheduler-side (runq, park, wake)
   runs on the main thread only. */
static __thread AhcTask *cur_task = &main_task;
static AhcTask *runq_head, *runq_tail;
static int n_workers;    /* live B1 spark workers (grows once) */

static size_t stack_guard_pg;        /* one page, PROT_NONE */

const char *ahc_last_error(void) {
  return cur_task->err_msg;
}

jmp_buf *ahc_err_frame(void) {
  if (cur_task->err_depth == AHC_ERR_DEPTH)
    ahc_die("FFI: entry functions nested too deeply");
  cur_task->err_msg[0] = 0;
  return &cur_task->err_stack[cur_task->err_depth++];
}

void ahc_err_disarm(void) {
  if (cur_task->err_depth > 0) cur_task->err_depth--;
}

static void die_unwind_if_armed(const char *msg) {
  if (cur_task->err_depth > 0) {
    size_t i = 0;
    while (msg[i] && i + 1 < sizeof cur_task->err_msg) {
      cur_task->err_msg[i] = msg[i];
      i++;
    }
    cur_task->err_msg[i] = 0;
    longjmp(cur_task->err_stack[--cur_task->err_depth], 1);
  }
}

/* ----- the scheduler --------------------------------------------- */

static void runq_push(AhcTask *t) {
  t->qnext = NULL;
  if (runq_tail) runq_tail->qnext = t;
  else runq_head = t;
  runq_tail = t;
}

static AhcTask *runq_pop(void) {
  AhcTask *t = runq_head;
  if (t) {
    runq_head = t->qnext;
    if (!runq_head) runq_tail = NULL;
  }
  return t;
}

/* ----- scheduler-integrated IO (M127, io-design-note.md) -------
   Tasks parked on a file descriptor sit on this list in
   REGISTRATION ORDER. When the run queue drains and the list is
   non-empty the scheduler blocks in poll(2) - an idle program
   costs nothing - and wakes the ready waiters in registration
   order, so the schedule stays reproducible. Membership on the
   list is what "armed" means; there is no sentinel fd. */

static AhcTask *iow_head, *iow_tail;

static void iow_add(AhcTask *t, int fd, short ev) {
  t->wait_fd = fd;
  t->wait_ev = ev;
  t->ionext = NULL;
  if (iow_tail) iow_tail->ionext = t;
  else iow_head = t;
  iow_tail = t;
}

static void iow_remove(AhcTask *t) {
  AhcTask *prev = NULL, *p = iow_head;
  while (p) {
    if (p == t) {
      if (prev) prev->ionext = p->ionext;
      else iow_head = p->ionext;
      if (iow_tail == p) iow_tail = prev;
      p->ionext = NULL;
      return;
    }
    prev = p;
    p = p->ionext;
  }
}

static void wake(AhcTask *t);

/* Run queue empty: block in poll over every parked fd waiter and
   wake the ready ones in registration order. 0 = nobody is
   waiting on an fd, i.e. a genuine deadlock. */
static int io_poll_block(void) {
  int n = 0, i, rc;
  AhcTask *t;
  struct pollfd *pf;
  AhcTask **owner;
  for (t = iow_head; t; t = t->ionext)
    if (t->state == 1) n++;
  if (n == 0) return 0;
  pf = (struct pollfd *)malloc(sizeof(struct pollfd) * (size_t)n);
  owner = (AhcTask **)malloc(sizeof(AhcTask *) * (size_t)n);
  if (!pf || !owner) ahc_die("out of memory");
  i = 0;
  for (t = iow_head; t; t = t->ionext)
    if (t->state == 1) {
      pf[i].fd = t->wait_fd;
      pf[i].events = t->wait_ev;
      pf[i].revents = 0;
      owner[i] = t;
      i++;
    }
  do {
    rc = poll(pf, (nfds_t)n, -1);
  } while (rc < 0 && errno == EINTR);
  if (rc < 0) ahc_die("poll failed");
  for (i = 0; i < n; i++)
    if (pf[i].revents && owner[i]->state == 1)
      wake(owner[i]);       /* error/hangup wake too: the caller's
                               own read reports the story */
  free(pf);
  free(owner);
  return 1;
}

/* Switch to the next runnable task. Requeue_self distinguishes a
   voluntary yield (still runnable) from a park (blocked) or death
   (never runnable again). */
static void sched_switch(int requeue_self) {
  AhcTask *self = cur_task;
  AhcTask *nxt;
  if (requeue_self) runq_push(self);
  nxt = runq_pop();
  while (!nxt) {
    if (!io_poll_block())
      ahc_die("deadlock: all green threads blocked");
    nxt = runq_pop();
  }
  if (nxt == self) return;
#ifdef AHC_GC_OWN
  /* The own collector reads parked extents directly; no
     registration calls, just the bookkeeping. */
  if (self->state < 2)
    self->parked_lo = (char *)&self - 1024;    /* slack below sp */
#endif
#ifdef AHC_USE_BOEHM
  {
    struct GC_stack_base sb;
    if (self->state < 2) {       /* a dying stack holds nothing */
      self->parked_lo = (char *)&sb - 1024;    /* slack below sp */
      GC_add_roots(self->parked_lo, self->stack_top);
    }
    if (nxt->parked_lo) {
      GC_remove_roots(nxt->parked_lo, nxt->stack_top);
      nxt->parked_lo = NULL;
    }
    sb.mem_base = nxt->stack_top;
    GC_set_stackbottom(NULL, &sb);
  }
#endif
  cur_task = nxt;
  swapcontext(&self->ctx, &nxt->ctx);
}

/* The scheduling point: rotate iff someone else is runnable, so a
   program with one task pays one pointer test. */
static void maybe_yield(void) {
  if (runq_head) sched_switch(1);
}

static void park(void) {
  cur_task->state = 1;
  sched_switch(0);
  cur_task->state = 0;
}

static void wake(AhcTask *t) {
  if (t->state >= 2) return;   /* died while parked (deadlock path) */
  t->state = 0;
  runq_push(t);
}

static void waitlist_append(AhcTask **list, AhcTask *t) {
  t->qnext = NULL;
  while (*list) list = &(*list)->qnext;
  *list = t;
}

void ahc_die(const char *msg) {
  die_unwind_if_armed(msg);
  fputs("ahc: ", stderr);
  fputs(msg, stderr);
  fputc('\n', stderr);
  exit(1);
}

/* Same, but the exiting print carries no "ahc: " prefix (the
   refinement-violation message format). */
static void ahc_die_raw(const char *msg) __attribute__((noreturn));
static void ahc_die_raw(const char *msg) {
  die_unwind_if_armed(msg);
  fputs(msg, stderr);
  fputc('\n', stderr);
  exit(1);
}

/* Die with prefix + a Haskell string as the message. */
static void die_msg_list(const char *prefix, AhcNode *cell)
  __attribute__((noreturn));
static void die_msg_list(const char *prefix, AhcNode *cell) {
  char buf[512];
  size_t n = 0;
  while (*prefix && n + 1 < sizeof buf)
    buf[n++] = *prefix++;
  cell = ahc_eval(cell);
  while (cell->tag == AHC_CON && cell->u.con.contag == 2) {
    if (n + 1 < sizeof buf)
      buf[n++] = (char)ahc_eval(cell->u.con.fields[0])->u.c;
    cell = ahc_eval(cell->u.con.fields[1]);
  }
  buf[n] = 0;
  ahc_die(buf);
}

#ifdef AHC_GC_OWN
/* ----- the own allocator, stage C1 (leak mode) -------------------
   docs/collector-design-note.md section 2. One large virtual
   reservation carved into 64KB-aligned blocks; each block header
   records kind and size class (C2's tracer will read both, and
   block alignment makes pointer-to-header a mask). Every mutator
   thread bump-allocates from its own active block per kind and
   class - the fast path is three instructions and takes no lock;
   the pool lock is paid once per 64KB. No collection yet: C1
   exists to prove the allocation story (parallel scaling AND
   sequential parity) before a single mark bit exists. Fresh
   commits are zero pages and leak mode never recycles, so the
   zeroed-memory invariant holds for free. */

#define OWN_BLOCK (64u * 1024)
#define OWN_HDR 64
#define OWN_CHUNK (16u * 1024 * 1024)
#define OWN_RESERVE (64ul << 30)        /* virtual; committed lazily */
#define OWN_MAX_SMALL 128
#define OWN_NCLASS 16
#define OWN_NKIND 4                     /* node, ptrarr, misc, large */

typedef struct OwnBlock {
  uint32_t kind;
  uint32_t size_class;                  /* object bytes; large: total */
  uint32_t bump;                        /* next free offset */
  uint32_t nblocks;                     /* run length (large > 1) */
  uint32_t gc_active;                   /* being bumped: sweep skips */
  uint32_t epoch;                       /* last GC cycle with allocs */
  uint32_t free_count;                  /* slots on free_head */
  void *free_head;                      /* sweep-built slot list */
  struct OwnBlock *next;
} OwnBlock;

static char *own_base, *own_commit, *own_end;
static OwnBlock *own_pool;           /* fed by the C2 sweep */
static pthread_mutex_t own_mx = PTHREAD_MUTEX_INITIALIZER;
static long own_blocks_out[OWN_NKIND];   /* __atomic counters */
static __thread OwnBlock *own_active[3][OWN_NCLASS];
/* Each thread carves blocks from a privately-held chunk, so the
   global lock (and the mprotect inside it) is paid once per 16MB,
   not once per block - the pool mutex showed up in the first C1
   profile at 4 workers. */
static __thread char *own_chunk_ptr, *own_chunk_end;

/* C2 side tables. Block states let the conservative filter and
   the sweep interpret any candidate address without trusting the
   64-byte headers (a large run's interior blocks hold payload
   where a header would be). The mark bitmap is one bit per 8
   heap bytes, uniform across size classes, committed in lockstep
   with heap chunks (1/64 of the chunk size - 1.6%). */
enum {
  OWN_B_VIRGIN = 0,      /* never handed out (or thread-chunk) */
  OWN_B_SMALL, OWN_B_LARGE_HEAD, OWN_B_LARGE_TAIL, OWN_B_FREE
};
#define OWN_MAX_BLOCKS (OWN_RESERVE / OWN_BLOCK)
static unsigned char *own_bstate;        /* one byte per block */
static unsigned char *own_marks;         /* 1 bit / 8 heap bytes */
static OwnBlock *own_partial[3][OWN_NCLASS];  /* free-slot blocks */
static __thread void *own_free_tls[3][OWN_NCLASS];
static long own_since_gc;                /* bytes handed out */
static long own_live_bytes;              /* after last sweep */
static long own_gc_count;
static int own_paranoid_level;
static int own_madvise;          /* AHC_OWN_MADVISE=1: RSS over speed */
/* Phase timing: the C4 precondition. The design note admits
   parallel marking ONLY if a measured profile shows mark time
   dominating after C3 - so the collector measures itself, and the
   numbers decide. AHC_OWN_STATS prints them. */
static double own_t_mark, own_t_sweep, own_t_rendezvous;
static double own_t_start;

static double own_now(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}
static long own_minors_since_major;
static long own_live_at_major;
static long own_minor_count;
static int own_in_gc;

static void own_maybe_collect(void);     /* fwd, end of file */
static void own_safepoint(void);         /* fwd, end of file */

/* C3: the write barrier. Laziness's gift (design note, req. 4):
   the only PURE-graph mutation is the thunk IND update, so this
   is the single hot barrier site (plus the channel tail append,
   cold). An old (marked) object that gains an edge is logged in
   a per-thread sequential store buffer and re-traced by the next
   minor collection. */
#define AHC_OWN_NSLOTS (33 + 1)
static void *own_ssb_seg[AHC_OWN_NSLOTS];
static size_t own_ssb_n[AHC_OWN_NSLOTS],
  own_ssb_cap[AHC_OWN_NSLOTS];

static void own_remember(void *o) {
  int s = 0;                     /* patched below: my_deque TLS */
  extern int ahc_bump_slot_hint(void);
  s = ahc_bump_slot_hint();
  if (own_ssb_n[s] == own_ssb_cap[s]) {
    own_ssb_cap[s] = own_ssb_cap[s] ? own_ssb_cap[s] * 2 : 4096;
    own_ssb_seg[s] = realloc(own_ssb_seg[s],
                             own_ssb_cap[s] * sizeof(void *));
    if (!own_ssb_seg[s]) ahc_die("own gc: remembered set");
  }
  ((void **)own_ssb_seg[s])[own_ssb_n[s]++] = o;
}

static void own_write_barrier(void *o) {
  size_t i;
  char *lim;
  if (!own_base) return;
  /* own_commit moves under own_mx; the barrier reads it lock-free
     (atomic - TSan finding). A stale limit is harmless: barrier
     targets are existing heap objects, always below the frontier. */
  lim = (char *)__atomic_load_n(&own_commit, __ATOMIC_RELAXED);
  if ((char *)o < own_base || (char *)o >= lim) return;
  i = (size_t)((char *)o - own_base) >> 3;
  if (own_marks[i >> 3] & (unsigned char)(1u << (i & 7)))
    own_remember(o);
}

static size_t own_block_index(void *p) {
  return (size_t)((char *)p - own_base) / OWN_BLOCK;
}

static void own_reserve(void) {
  size_t sz = OWN_RESERVE + OWN_BLOCK;
  char *m = (char *)mmap(NULL, sz, PROT_NONE,
                         MAP_PRIVATE | MAP_ANON, -1, 0);
  if (m == MAP_FAILED) ahc_die("own gc: cannot reserve the heap");
  own_base = (char *)(((uintptr_t)m + OWN_BLOCK - 1)
                      & ~(uintptr_t)(OWN_BLOCK - 1));
  own_commit = own_base;
  own_end = m + sz;
  own_bstate = (unsigned char *)calloc(OWN_MAX_BLOCKS, 1);
  if (!own_bstate) ahc_die("own gc: cannot allocate block table");
  own_marks = (unsigned char *)mmap(NULL, OWN_RESERVE / 64,
                                    PROT_NONE,
                                    MAP_PRIVATE | MAP_ANON, -1, 0);
  if (own_marks == MAP_FAILED)
    ahc_die("own gc: cannot reserve the mark bitmap");
}

/* Both called under own_mx. */
static char *own_commit_span(size_t sz) {
  char *p;
  if (!own_base) own_reserve();
  if (own_commit + sz > own_end)
    ahc_die("own gc: reservation exhausted");
  if (mprotect(own_commit, sz, PROT_READ | PROT_WRITE) != 0)
    ahc_die("own gc: cannot commit heap pages");
  /* commit the matching mark-bitmap slice (1/64, rounded out) */
  {
    size_t lo = (size_t)(own_commit - own_base) / 64;
    size_t hi = (size_t)(own_commit + sz - own_base) / 64;
    size_t pg = stack_guard_pg ? stack_guard_pg : 4096;
    lo &= ~(pg - 1);
    hi = (hi + pg - 1) & ~(pg - 1);
    if (mprotect(own_marks + lo, hi - lo,
                 PROT_READ | PROT_WRITE) != 0)
      ahc_die("own gc: cannot commit the mark bitmap");
  }
  p = own_commit;
  __atomic_store_n(&own_commit, own_commit + sz, __ATOMIC_RELAXED);
  return p;
}

static OwnBlock *own_get_block(uint32_t kind, uint32_t cls_bytes) {
  OwnBlock *b = NULL;
  own_safepoint();
  own_maybe_collect();
  /* the sweep's recycled blocks first (locality is the point);
     the unlocked pre-check is an atomic load - TSan's second C2
     finding was this probe racing the sweep's pushes */
  if (__atomic_load_n(&own_pool, __ATOMIC_RELAXED)) {
    pthread_mutex_lock(&own_mx);
    b = (OwnBlock *)__atomic_load_n(&own_pool, __ATOMIC_RELAXED);
    if (b) __atomic_store_n(&own_pool, b->next, __ATOMIC_RELAXED);
    pthread_mutex_unlock(&own_mx);
    if (b) memset((char *)b + OWN_HDR, 0, OWN_BLOCK - OWN_HDR);
  }
  if (!b) {
    if (own_chunk_ptr + OWN_BLOCK > own_chunk_end) {
      pthread_mutex_lock(&own_mx);
      own_chunk_ptr = own_commit_span(OWN_CHUNK);
      pthread_mutex_unlock(&own_mx);
      own_chunk_end = own_chunk_ptr + OWN_CHUNK;
    }
    b = (OwnBlock *)own_chunk_ptr;
    own_chunk_ptr += OWN_BLOCK;
  }
  __atomic_fetch_add(&own_blocks_out[kind], 1, __ATOMIC_RELAXED);
  __atomic_fetch_add(&own_since_gc, OWN_BLOCK, __ATOMIC_RELAXED);
  b->kind = kind;
  b->size_class = cls_bytes;
  b->bump = OWN_HDR;
  b->nblocks = 1;
  b->next = NULL;
  b->epoch = (uint32_t)own_gc_count;
  own_bstate[own_block_index(b)] = OWN_B_SMALL;
  return b;
}

static void *own_alloc_large(uint32_t kind, size_t n) {
  size_t nb = (n + OWN_HDR + OWN_BLOCK - 1) / OWN_BLOCK;
  size_t i, bi;
  OwnBlock *b;
  own_safepoint();
  own_maybe_collect();
  pthread_mutex_lock(&own_mx);
  b = (OwnBlock *)own_commit_span(nb * OWN_BLOCK);
  pthread_mutex_unlock(&own_mx);
  __atomic_fetch_add(&own_blocks_out[3], 1, __ATOMIC_RELAXED);
  __atomic_fetch_add(&own_since_gc, (long)(nb * OWN_BLOCK),
                     __ATOMIC_RELAXED);
  b->kind = kind;                /* the REAL kind; large is a state */
  b->size_class = (uint32_t)n;
  b->bump = OWN_HDR;
  b->nblocks = (uint32_t)nb;
  b->next = NULL;
  b->epoch = (uint32_t)own_gc_count;
  bi = own_block_index(b);
  own_bstate[bi] = OWN_B_LARGE_HEAD;
  for (i = 1; i < nb; i++) own_bstate[bi + i] = OWN_B_LARGE_TAIL;
  return (char *)b + OWN_HDR;
}

static void *own_adopt_partial(int kind, size_t cls) {
  OwnBlock *b;
  pthread_mutex_lock(&own_mx);
  b = own_partial[kind][cls];
  if (b) own_partial[kind][cls] = b->next;
  pthread_mutex_unlock(&own_mx);
  if (!b) return NULL;
  b->next = NULL;
  b->epoch = (uint32_t)own_gc_count;    /* it is about to be dirty */
  own_free_tls[kind][cls] = b->free_head;
  b->free_head = NULL;
  b->free_count = 0;
  return own_free_tls[kind][cls];
}

static void *own_alloc(int kind, size_t n) {
  size_t cls;
  OwnBlock *b;
  void *p;
  n = (n + 7) & ~(size_t)7;
  if (n == 0) n = 8;
  if (n > OWN_MAX_SMALL) return own_alloc_large((uint32_t)kind, n);
  cls = (n >> 3) - 1;
  /* recycled slots first: object-grain reuse is what keeps RSS
     at Boehm's scale (block-grain alone ratcheted 50x on b_map) */
  p = own_free_tls[kind][cls];
  if (p) {
    own_free_tls[kind][cls] = *(void **)p;
    memset(p, 0, n);
    return p;
  }
  b = own_active[kind][cls];
  if (!b || b->bump + n > OWN_BLOCK) {
    if ((p = own_adopt_partial(kind, cls)) != NULL) {
      own_free_tls[kind][cls] = *(void **)p;
      memset(p, 0, n);
      return p;
    }
    b = own_get_block((uint32_t)kind, (uint32_t)n);
    own_active[kind][cls] = b;
  }
  p = (char *)b + b->bump;
  b->bump += (uint32_t)n;
  return p;
}

static void own_stats(void) {
  fprintf(stderr,
          "own gc: blocks node %ld ptrarr %ld misc %ld large %ld"
          " (%.1f MB committed)\n",
          own_blocks_out[0], own_blocks_out[1],
          own_blocks_out[2], own_blocks_out[3],
          (double)(own_commit - own_base) / (1024.0 * 1024.0));
  {
    double wall = own_now() - own_t_start;
    double gc = own_t_mark + own_t_sweep + own_t_rendezvous;
    fprintf(stderr,
            "own gc: %ld collections (%ld minor), %.1f MB live\n",
            own_gc_count, own_minor_count,
            (double)own_live_bytes / (1024.0 * 1024.0));
    fprintf(stderr,
            "own gc: wall %.3fs | gc %.3fs (%.1f%%) = mark %.3fs"
            " (%.1f%% of gc) + sweep %.3fs + rendezvous %.3fs\n",
            wall, gc, wall > 0 ? 100.0 * gc / wall : 0.0,
            own_t_mark, gc > 0 ? 100.0 * own_t_mark / gc : 0.0,
            own_t_sweep, own_t_rendezvous);
  }
}
#endif /* AHC_GC_OWN */

#if defined(AHC_GC_OWN)
#define AHC_ALLOC_NODE() own_alloc(0, sizeof(AhcNode))
#define AHC_ALLOC_ENV(k) own_alloc(1, sizeof(AhcNode *) * (size_t)(k))
#endif

/* Per-thread free lists refilled by GC_malloc_many. The installed
   collector takes a GLOBAL mutex in GC_malloc (no thread-local
   allocation in the brew build), and a graph reducer allocates on
   nearly every reduction step - under B1 that lock was the whole
   ballgame (measured: workers converted sparks and the clock did
   not move). GC_malloc_many hands back a LIST of same-size
   objects under one lock; parked on a per-thread free list, the
   lock is amortized across a batch while every object stays an
   ordinary, individually-collectable GC object - no retention
   change. (A bump-arena version was tried first: sequential time
   went 2.6x WORSE from block-grain retention. The collector's own
   batching API is the right tool.) List heads live in a static
   (scanned) array, not in TLS alone - TLS is invisible to the
   collector, and a free chain must stay reachable. */
#ifdef AHC_USE_BOEHM
#define AHC_NCLASS 8                    /* 8..64 bytes, 8-byte step */
#define AHC_NSLOTS (33 + 1)             /* main + workers */
/* One 128-byte-aligned row per thread: every allocation WRITES its
   row's list head, and rows sharing a cache line would ping-pong
   between cores on every single allocation. */
static void *hot_free[AHC_NSLOTS][16]
  __attribute__((aligned(128)));        /* scanned roots */
static __thread void **my_hot_free;
extern int ahc_bump_slot_hint(void);    /* fwd: my_deque, below */

static void *ahc_hot_alloc(size_t n) {
  size_t cls;
  void *p;
  n = (n + 7) & ~(size_t)7;
  if (n == 0 || n > AHC_NCLASS * 8) {
    p = GC_MALLOC(n);
    if (!p) ahc_die("out of memory");
    return p;
  }
  if (!my_hot_free) my_hot_free = hot_free[ahc_bump_slot_hint()];
  cls = (n >> 3) - 1;
  p = my_hot_free[cls];
  if (!p) {
    p = GC_malloc_many(n);
    if (!p) ahc_die("out of memory");
  }
  my_hot_free[cls] = GC_NEXT(p);
  GC_NEXT(p) = NULL;    /* restore the zeroed-memory invariant */
  return p;
}
#define AHC_ALLOC_HOT(n) ahc_hot_alloc(n)
#else
#define AHC_ALLOC_HOT(n) AHC_ALLOC(n)
#endif

#ifndef AHC_ALLOC_NODE
#define AHC_ALLOC_NODE() AHC_ALLOC_HOT(sizeof(AhcNode))
#define AHC_ALLOC_ENV(k) \
  AHC_ALLOC_HOT(sizeof(AhcNode *) * (size_t)(k))
#endif

static AhcNode *alloc_node(void) {
  AhcNode *n = (AhcNode *)AHC_ALLOC_NODE();
  if (!n) ahc_die("out of memory");
  return n;
}

AhcNode **ahc_env(int n) {
  if (n == 0) return NULL;
  AhcNode **e = (AhcNode **)AHC_ALLOC_ENV(n);
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

/* THE CONSTRUCTION-ORDER INVARIANT (generational collector): an
   object must never gain a pointer to something allocated AFTER
   it without a write barrier. A collection can run between any
   two allocations, conservatively mark the half-built owner, and
   the sticky-marked owner's later-assigned child is then invisible
   to the next minor - it gets freed while referenced. (Found by
   AHC_OWN_PARANOID on b_sumfold: an old CON, fields young, fields
   freed.) So: components are allocated BEFORE their owner, and
   slot-fills store only values that already existed. The paranoid
   shadow-mark verifier is the enforcement tool. */
AhcNode *ahc_mk_con(int contag, int arity) {
  AhcNode **fields = arity ? ahc_env(arity) : NULL;
  AhcNode *n = alloc_node();
  n->tag = AHC_CON; n->u.con.contag = contag; n->u.con.arity = arity;
  n->u.con.fields = fields;
  return n;
}

/* Update-in-place graph reduction: the PRD's thunk model. */
/* One brief pause in a spin loop; be polite to the OS now and
   then. B1 spins are bounded: a blackhole's owner is always making
   progress on some OS thread (pure evaluation cannot block), so a
   spin ends when the owner updates. */
#ifdef AHC_GC_OWN
static void own_safepoint(void);
#endif

/* Wall-clock budget for a single blackhole spin. Returns 1 once
   the budget is exhausted. First call stamps the start. */
/* Set ONCE in ahc_rts_init, while the runtime is still
   single-threaded. Initialising it lazily here instead was a data
   race TSan caught immediately: every worker executes this path,
   and a plain 8-byte store to a shared double from several of them
   at once is exactly the kind of thing the sanitiser exists to
   find. Read-only afterwards. */
static double ahc_spin_limit = 120.0;

static int ahc_spin_expired(double *t0) {
  struct timespec ts;
  double now;
  if (ahc_spin_limit == 0.0) return 0;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  now = (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
  if (*t0 == 0.0) { *t0 = now; return 0; }
  return (now - *t0) > ahc_spin_limit;
}

static void spin_pause(unsigned long *iters) {
#ifdef AHC_GC_OWN
  own_safepoint();
#endif
#if defined(__x86_64__)
  __builtin_ia32_pause();
#else
  __asm__ volatile("" ::: "memory");
#endif
  if ((++*iters & 1023) == 0) sched_yield();
}

/* The thunk protocol (design note 7.3). Claim is a CAS to the
   transient AHC_CLAIM, then owner/waiters are written, then the
   tag goes AHC_BLACKHOLE with release - so anyone who reads
   BLACKHOLE (acquire) sees a valid owner. Update stores the
   payload, then the IND tag, both release; the dispatch load is
   acquire. Green-vs-green contention parks (Phase A, unchanged);
   any contention involving a worker spins, because workers never
   park and their victims never wait long. */
#ifdef AHC_GC_OWN
void ahc_spin_report_gc(int nw);
#endif
static void ahc_spin_report(AhcNode *n, void *owner, AhcTask *self);

AhcNode *ahc_eval(AhcNode *n) {
  unsigned long spins = 0;
  double spin_t0 = 0.0;        /* watchdog stamp, set on first spin */
  for (;;) {
    switch (__atomic_load_n(&n->tag, __ATOMIC_ACQUIRE)) {
    case AHC_IND:
      n = (AhcNode *)__atomic_load_n(&n->u.ind, __ATOMIC_ACQUIRE);
      break;
    case AHC_THUNK: {
      /* code/env are read only AFTER winning the claim: between
         CLAIM and the BLACKHOLE publish the winner has the node
         to itself, and a loser's speculative read would race the
         winner's owner store into the same union words (TSan
         found exactly that). */
      AhcCode code;
      AhcNode **env;
      AhcTag expect = AHC_THUNK;
      if (!__atomic_compare_exchange_n(&n->tag, &expect, AHC_CLAIM,
                                       0, __ATOMIC_ACQ_REL,
                                       __ATOMIC_ACQUIRE))
        break;                 /* lost the race - redispatch */
      code = n->u.thunk.code;
      env = n->u.thunk.env;
      __atomic_store_n(&n->u.bh.owner, cur_task, __ATOMIC_RELAXED);
      n->u.bh.waiters = NULL;
      __atomic_store_n(&n->tag, AHC_BLACKHOLE, __ATOMIC_RELEASE);
      {
        AhcNode *v = ahc_eval(code(env));
        /* wake tasks parked on this thunk (FIFO), then update.
           Waiters exist only on green-owned blackholes, and green
           tasks share one OS thread - reading the list before the
           payload store overwrites its word is race-free. */
        AhcTask *w = (AhcTask *)n->u.bh.waiters;
        __atomic_store_n(&n->u.ind, v, __ATOMIC_RELEASE);
        __atomic_store_n(&n->tag, AHC_IND, __ATOMIC_RELEASE);
#ifdef AHC_GC_OWN
        own_write_barrier(n);
#endif
        while (w) {
          AhcTask *nx = w->qnext;
          wake(w);
          w = nx;
        }
        n = v;
      }
      break;
    }
    case AHC_CLAIM:
      spin_pause(&spins);      /* owner is publishing; momentary */
      break;
    case AHC_BLACKHOLE: {
      /* The owner WORD may be stale: it shares its union slot
         with u.ind, so a racing updater can overwrite it with the
         payload between our tag load and here. Every use below is
         therefore a pointer COMPARE, never a dereference - a
         payload pointer can equal no task's address. */
      AhcTask *owner =
        (AhcTask *)__atomic_load_n(&n->u.bh.owner, __ATOMIC_ACQUIRE);
      if (owner == cur_task) ahc_die("<<loop>>");
      if (cur_task->is_worker
          || __atomic_load_n(&n_workers, __ATOMIC_RELAXED) > 0) {
        /* Any contention involving workers spins: the owner is
           making progress on some OS thread (or is a green task
           main will reschedule), and workers never park - that is
           what keeps them deadlock-free by construction (7.3).
           The cost, documented: with workers live, a genuinely
           CYCLIC cross-task dependency spins instead of reporting
           deadlock; without par the Phase A reports are intact.

           A spinner MUST NOT help (run another spark) while it
           waits, however tempting the idle cycles are. Helping
           was tried in C1 and had to be removed in M109: a thread
           that is WAITING must not ACQUIRE, because the spark it
           helps with blackholes fresh thunks that the thread it
           is waiting for may then need - a dependency cycle the
           program never contained. Plain spinning is safe for the
           opposite reason: ownership follows the program's own
           dependency graph, so a cycle there IS a <<loop>>.
           b_parsort at 2 workers deadlocked on exactly this.

           WATCHDOG (M119): a spin that never ends must be a
           reported outcome, not a hang - the same principle
           M102 applied to green-thread deadlock. A rare
           parallel hang was observed once (main spinning here
           while every worker sat idle in its nap loop, 2.5
           HOURS before a human noticed) and has not been
           reproducible in 24 attempts, so it cannot yet be
           fixed - but it can be made loud. AHC_SPIN_LIMIT sets
           the budget in seconds; 0 disables. */
        if ((spins & 0xFFFFF) == 0 && ahc_spin_expired(&spin_t0)) {
          ahc_spin_report(n, owner, cur_task);
          ahc_die("blackhole spin exceeded AHC_SPIN_LIMIT: the"
                  " owning thread is making no progress (see"
                  " collector-design-note.md section 18)");
        }
        spin_pause(&spins);
        break;
      }
      /* No workers exist: pure Phase A, one OS thread. Park until
         the owner updates. Self-dependency died <<loop>> above;
         if the owner died mid-force the thunk never updates and
         the scheduler's deadlock detector reports it. */
      waitlist_append((AhcTask **)&n->u.bh.waiters, cur_task);
      park();
      break;
    }
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
  AhcNode *tagn = ahc_mk_int(contag);       /* children first */
  AhcNode *arn = ahc_mk_int(arity);
  AhcNode **e = ahc_env(2 + arity);
  e[0] = tagn; e[1] = arn;
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
  AhcNode *w = ahc_mk_int((long)(uintptr_t)what);  /* child first */
  AhcNode **e = ahc_env(1);
  e[0] = w;
  return ahc_mk_thunk(missing_code, e);
}

AhcNode *ahc_mk_selector(int index) {
  AhcNode *ix = ahc_mk_int(index);          /* child first */
  AhcNode **e = ahc_env(1);
  e[0] = ix;
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
    AhcNode *ch = ahc_mk_char((unsigned char)s[i - 1]);
    AhcNode *c = ahc_mk_con(CONS_TAG, 2);   /* child first */
    c->u.con.fields[0] = ch;
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
  AhcNode *fn = ahc_mk_int((long)(uintptr_t)f);   /* child first */
  AhcNode **e = ahc_env(1);
  e[0] = fn;
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
  AhcNode *fn = ahc_mk_int((long)(uintptr_t)f);   /* child first */
  AhcNode **e = ahc_env(1);
  e[0] = fn;
  return ahc_mk_fun(prim3_first, e);
}

typedef AhcNode *(*Prim1)(AhcNode *);

static AhcNode *prim1_apply(AhcNode **env, AhcNode *a) {
  Prim1 f = (Prim1)(uintptr_t)env[0]->u.i;
  return f(a);
}

static AhcNode *mk_prim1(Prim1 f) {
  AhcNode *fn = ahc_mk_int((long)(uintptr_t)f);   /* child first */
  AhcNode **e = ahc_env(1);
  e[0] = fn;
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
  {                                         /* children first */
    AhcNode *fn = ahc_mk_int((long)(uintptr_t)f);
    AhcNode *ar = ahc_mk_int(arity);
    e = ahc_env(2 + arity);
    e[0] = fn;
    e[1] = ar;
  }
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
  AhcNode *v = ahc_mk_int(n);               /* child first */
  AhcNode **e = ahc_env(1);
  e[0] = v;
  return ahc_mk_thunk(enum_from_code, e);
}

static AhcNode *enum_from_code(AhcNode **env) {
  long n = env[0]->u.i;
  AhcNode *hd = ahc_mk_int(n);              /* children first */
  AhcNode *tl = mk_enum_from(n + 1);
  AhcNode *c = ahc_mk_con(CONS_TAG, 2);
  c->u.con.fields[0] = hd;
  c->u.con.fields[1] = tl;
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
  AhcNode *v = ahc_mk_int(n);               /* children first */
  AhcNode *st = ahc_mk_int(step);
  AhcNode **e = ahc_env(2);
  e[0] = v;
  e[1] = st;
  return ahc_mk_thunk(enum_ft_code, e);
}

static AhcNode *enum_ft_code(AhcNode **env) {
  long n = env[0]->u.i, step = env[1]->u.i;
  AhcNode *hd = ahc_mk_int(n);              /* children first */
  AhcNode *tl = mk_enum_ft(n + step, step);
  AhcNode *c = ahc_mk_con(CONS_TAG, 2);
  c->u.con.fields[0] = hd;
  c->u.con.fields[1] = tl;
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
    AhcNode *v = ahc_mk_int(lo + i * step);  /* child first */
    AhcNode *cc = ahc_mk_con(CONS_TAG, 2);
    cc->u.con.fields[0] = v;
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
    AhcNode *v = ahc_mk_int(i);                 /* child first */
    AhcNode *c = ahc_mk_con(CONS_TAG, 2);
    c->u.con.fields[0] = v;
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
  fflush(stdout);   /* output already produced must precede the die */
  die_msg_list("error: ", a);
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
    die_msg_list("", msg);
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
  AhcNode *r;
  maybe_yield();               /* the deterministic scheduling point */
  r = ahc_apply(env[0], w);
  return ahc_apply(ahc_apply(env[1], r), w);
}

static AhcNode *p_bind_io(AhcNode *m, AhcNode *k) {
  AhcNode **e = ahc_env(2);
  e[0] = m; e[1] = k;
  return ahc_mk_fun(io_bind, e);
}

/* thenIO m k = \w -> m w `seq-ish` k w */
static AhcNode *io_then(AhcNode **env, AhcNode *w) {
  maybe_yield();               /* the deterministic scheduling point */
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

/* ----- green-thread prims (Phase A) ------------------------------ */

/* Scope, Task, and Chan cross the Haskell boundary as Int indices
   into these registries - the Handle discipline (M78): a stale
   index dies with a clean message, never a dangling pointer. The
   tables are AHC_ALLOC'd and reachable from statics, so the
   collector sees every task's stack, action, result, and every
   queued channel value. */

typedef struct AhcChanCell {
  AhcNode *v;
  struct AhcChanCell *next;
} AhcChanCell;

/* A selector (selectRecv / waitReadOr) waits on SEVERAL sources at
   once, and a task has only one qnext link - so selectors enlist
   through per-channel cells instead. malloc'd: they never hold a
   node (the value goes straight to the task's xfer at send time);
   the owner unlinks its cells when it resumes. */
typedef struct AhcSelCell {
  AhcTask *t;                /* NULL once served or abandoned */
  long index;                /* the alternative's position */
  struct AhcSelCell *next;
} AhcSelCell;

typedef struct AhcChan {
  AhcChanCell *head, *tail;  /* sent, not yet received (FIFO) */
  AhcTask *recv_waiters;     /* parked receivers (FIFO) */
  AhcSelCell *sel_waiters;   /* parked selectors (FIFO) */
} AhcChan;

static void sel_enlist(AhcChan *c, AhcTask *t, long index) {
  AhcSelCell *cell = (AhcSelCell *)malloc(sizeof(AhcSelCell));
  AhcSelCell **p = &c->sel_waiters;
  if (!cell) ahc_die("out of memory");
  cell->t = t;
  cell->index = index;
  cell->next = NULL;
  while (*p) p = &(*p)->next;
  *p = cell;
}

/* Drop this task's cells (and any dead ones met on the way). */
static void sel_unlink(AhcChan *c, AhcTask *t) {
  AhcSelCell **p = &c->sel_waiters;
  while (*p) {
    AhcSelCell *cell = *p;
    if (cell->t == t || cell->t == NULL) {
      *p = cell->next;
      free(cell);
    } else {
      p = &cell->next;
    }
  }
}

static AhcTask **task_reg;  static int task_n, task_cap;
static AhcScope **scope_reg; static int scope_n, scope_cap;
static AhcChan **chan_reg;  static int chan_n, chan_cap;

static int reg_add(void ***tab, int *n, int *cap, void *p) {
  if (*n == *cap) {
    int nc = *cap ? *cap * 2 : 16;
    void **nt = (void **)AHC_ALLOC(sizeof(void *) * nc);
    int i;
    if (!nt) ahc_die("out of memory");
    for (i = 0; i < *n; i++) nt[i] = (*tab)[i];
    *tab = nt;
    *cap = nc;
  }
  (*tab)[*n] = p;
  return (*n)++;
}

static AhcTask *task_of(AhcNode *n, const char *who) {
  long i = ahc_eval(n)->u.i;
  if (i < 0 || i >= task_n || !task_reg[i]) ahc_die(who);
  return task_reg[i];
}

static AhcScope *scope_of(AhcNode *n, const char *who) {
  long i = ahc_eval(n)->u.i;
  if (i < 0 || i >= scope_n || !scope_reg[i]) ahc_die(who);
  return scope_reg[i];
}

static AhcChan *chan_of(AhcNode *n) {
  long i = ahc_eval(n)->u.i;
  if (i < 0 || i >= chan_n || !chan_reg[i])
    ahc_die("channel does not exist");
  return chan_reg[i];
}

/* Every spawned task starts here. The armed frame turns a runtime
   death (error, refinement violation, deadlock while parked) into
   state 3 with the message in err_msg - the process survives and
   await/scope-exit decide who inherits the failure. */
static void task_trampoline(int id) {
  AhcTask *t = task_reg[id];
  if (setjmp(*ahc_err_frame()) == 0) {
    t->result = ahc_eval(ahc_apply(t->action, the_world));
    ahc_err_disarm();
    t->state = 2;
  } else {
    t->state = 3;
  }
  t->action = NULL;
  {
    AhcTask *w = t->join_waiters;
    t->join_waiters = NULL;
    while (w) {
      AhcTask *nx = w->qnext;
      wake(w);
      w = nx;
    }
  }
  sched_switch(0);             /* finished: never scheduled again */
  ahc_die("resumed a finished task");
}

/* scope f: open a scope, run f on its id, then JOIN every child in
   spawn order before returning (Ada's master rule). A child that
   failed and was never awaited fails the scope here. On exit the
   scope's ids are retired, so a Task or Scope value leaked past its
   scope dies cleanly instead of dangling. */
static AhcNode *io_scope(AhcNode **env, AhcNode *w) {
  AhcScope *sc = (AhcScope *)AHC_ALLOC(sizeof(AhcScope));
  AhcNode *r;
  int si, i;
  if (!sc) ahc_die("out of memory");
  sc->kids = NULL;
  sc->n = 0;
  sc->cap = 0;
  si = reg_add((void ***)&scope_reg, &scope_n, &scope_cap, sc);
  r = ahc_eval(ahc_apply(ahc_apply(env[0], ahc_mk_int(si)), w));
  for (i = 0; i < sc->n; i++) {  /* sc->n can grow while we join */
    AhcTask *k = sc->kids[i];
    while (k->state < 2) {
      waitlist_append(&k->join_waiters, cur_task);
      park();
    }
    if (k->state == 3 && !k->awaited)
      ahc_die(k->err_msg);
  }
  for (i = 0; i < sc->n; i++) {
    AhcTask *k = sc->kids[i];
    if (k->stack) {
      munmap(k->stack, AHC_TASK_STACK + stack_guard_pg);
      k->stack = NULL;
    }
    task_reg[k->id] = NULL;
  }
  scope_reg[si] = NULL;
  return r;
}

static AhcNode *p_scope(AhcNode *f) {
  AhcNode **e = ahc_env(1);
  e[0] = f;
  return ahc_mk_fun(io_scope, e);
}

/* spawn: the child goes to the TAIL of the run queue and the
   spawner keeps running - creation is not a scheduling point, so
   spawn order alone fixes the schedule. */
/* A green thread overflowing its reservation lands on the guard
   page; this handler (on an alternate signal stack) names the
   failure instead of leaving a corrupt-looking crash. */
static void stack_overflow_handler(int sig, siginfo_t *si, void *uc) {
  char *a = (char *)si->si_addr;
  int i;
  (void)uc;
  for (i = 0; i < task_n; i++) {
    AhcTask *t = task_reg[i];
    if (t && t->stack && a >= t->stack
        && a < t->stack + stack_guard_pg) {
      static const char msg[] =
        "ahc: green thread stack overflow\n";
      ssize_t r = write(2, msg, sizeof msg - 1);
      (void)r;
      _exit(1);
    }
  }
  signal(sig, SIG_DFL);        /* not ours: crash as before */
  raise(sig);
}

static AhcNode *io_spawn(AhcNode **env, AhcNode *w) {
  AhcScope *sc = scope_of(env[0], "spawn: scope already closed");
  AhcTask *t = (AhcTask *)AHC_ALLOC(sizeof(AhcTask));
  char *base;
  int id;
  (void)w;
  if (!t) ahc_die("out of memory");
  memset(t, 0, sizeof *t);
  base = (char *)mmap(NULL, AHC_TASK_STACK + stack_guard_pg,
                      PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANON, -1, 0);
  if (base == MAP_FAILED) ahc_die("spawn: cannot map a task stack");
  mprotect(base, stack_guard_pg, PROT_NONE);
  t->stack = base;
  t->stack_top = base + stack_guard_pg + AHC_TASK_STACK;
  t->action = env[1];
  id = reg_add((void ***)&task_reg, &task_n, &task_cap, t);
  t->id = id;
  if (getcontext(&t->ctx) != 0) ahc_die("spawn: getcontext failed");
  t->ctx.uc_stack.ss_sp = t->stack + stack_guard_pg;
  t->ctx.uc_stack.ss_size = AHC_TASK_STACK;
  t->ctx.uc_link = NULL;
  makecontext(&t->ctx, (void (*)(void))task_trampoline, 1, id);
  if (sc->n == sc->cap) {
    int nc = sc->cap ? sc->cap * 2 : 4;
    AhcTask **nk = (AhcTask **)AHC_ALLOC(sizeof(AhcTask *) * nc);
    int i;
    if (!nk) ahc_die("out of memory");
    for (i = 0; i < sc->n; i++) nk[i] = sc->kids[i];
    sc->kids = nk;
    sc->cap = nc;
  }
  sc->kids[sc->n++] = t;
  runq_push(t);
  return ahc_mk_int(id);
}

static AhcNode *p_spawn(AhcNode *si, AhcNode *act) {
  AhcNode **e = ahc_env(2);
  e[0] = si;
  e[1] = act;
  return ahc_mk_fun(io_spawn, e);
}

static AhcNode *io_await(AhcNode **env, AhcNode *w) {
  AhcTask *t = task_of(env[0], "await: task's scope already closed");
  (void)w;
  t->awaited = 1;
  while (t->state < 2) {
    waitlist_append(&t->join_waiters, cur_task);
    park();
  }
  if (t->state == 3) ahc_die(t->err_msg);
  return t->result;
}

static AhcNode *p_await(AhcNode *ti) {
  AhcNode **e = ahc_env(1);
  e[0] = ti;
  return ahc_mk_fun(io_await, e);
}

/* Channels are unbounded FIFO queues (GHC's Chan semantics, which
   keeps the shim a one-liner): send never blocks, recv parks when
   empty. Parked receivers are served strictly in arrival order. */
static AhcNode *io_chan_new(AhcNode **env, AhcNode *w) {
  AhcChan *c = (AhcChan *)AHC_ALLOC(sizeof(AhcChan));
  (void)env;
  (void)w;
  if (!c) ahc_die("out of memory");
  c->head = NULL;
  c->tail = NULL;
  c->recv_waiters = NULL;
  c->sel_waiters = NULL;
  return ahc_mk_int(reg_add((void ***)&chan_reg,
                            &chan_n, &chan_cap, c));
}

static AhcNode *io_chan_send(AhcNode **env, AhcNode *w) {
  AhcChan *c = chan_of(env[0]);
  AhcNode *v = env[1];         /* lazily: the thunk travels */
  AhcTask *r;
  (void)w;
  while ((r = c->recv_waiters) != NULL) {
    c->recv_waiters = r->qnext;
    /* == 1, not < 2: an fd-woken dual waiter still on this list
       must not be handed a second value (M127) */
    if (r->state == 1) {
      r->xfer = v;
      wake(r);
      return ahc_mk_con(UNIT_TAG, 0);
    }
  }
  {
    /* plain receivers outrank selectors; both FIFO - the pinned
       preference order (io-design-note.md part 2) */
    AhcSelCell *cell;
    for (cell = c->sel_waiters; cell; cell = cell->next) {
      if (cell->t && cell->t->state == 1) {
        cell->t->xfer = v;
        cell->t->sel_index = cell->index;
        wake(cell->t);
        cell->t = NULL;
        return ahc_mk_con(UNIT_TAG, 0);
      }
    }
  }
  {
    AhcChanCell *cell = (AhcChanCell *)AHC_ALLOC(sizeof(AhcChanCell));
    if (!cell) ahc_die("out of memory");
    cell->v = v;
    cell->next = NULL;
#ifdef AHC_GC_OWN
    if (c->tail) own_write_barrier(c->tail);
#endif
    if (c->tail) c->tail->next = cell;
    else c->head = cell;
    c->tail = cell;
  }
  return ahc_mk_con(UNIT_TAG, 0);
}

static AhcNode *p_chan_send(AhcNode *ci, AhcNode *x) {
  AhcNode **e = ahc_env(2);
  e[0] = ci;
  e[1] = x;
  return ahc_mk_fun(io_chan_send, e);
}

static AhcNode *io_chan_recv(AhcNode **env, AhcNode *w) {
  AhcChan *c = chan_of(env[0]);
  (void)w;
  if (c->head) {
    AhcChanCell *cell = c->head;
    c->head = cell->next;
    if (!c->head) c->tail = NULL;
    return cell->v;
  }
  waitlist_append(&c->recv_waiters, cur_task);
  park();
  {
    AhcNode *v = cur_task->xfer;
    cur_task->xfer = NULL;
    return v;
  }
}

static AhcNode *p_chan_recv(AhcNode *ci) {
  AhcNode **e = ahc_env(1);
  e[0] = ci;
  return ahc_mk_fun(io_chan_recv, e);
}

static AhcNode *io_task_yield(AhcNode **env, AhcNode *w) {
  (void)env;
  (void)w;
  maybe_yield();
  return ahc_mk_con(UNIT_TAG, 0);
}

/* ----- scheduler-integrated IO prims (M127) ---------------------
   io-design-note.md part 2. Maybe is tags 1/2 (Nothing/Just), a
   pair is the single tag-1 constructor, children first. */

#define NOTHING_TAG 1
#define JUST_TAG 2

static AhcNode *mk_nothing(void) {
  return ahc_mk_con(NOTHING_TAG, 0);
}

static AhcNode *mk_just(AhcNode *v) {
  AhcNode *c = ahc_mk_con(JUST_TAG, 1);
  c->u.con.fields[0] = v;
  return c;
}

/* waitRead / waitWrite: park until the fd is ready. Readiness is
   checked when the run queue drains - the cooperative contract. */
static AhcNode *io_wait_fd(AhcNode **env, AhcNode *w) {
  long fd = ahc_eval(env[0])->u.i;
  short ev = (short)ahc_eval(env[1])->u.i;
  (void)w;
  iow_add(cur_task, (int)fd, ev);
  park();
  iow_remove(cur_task);
  return ahc_mk_con(UNIT_TAG, 0);
}

static AhcNode *p_wait_read(AhcNode *fd) {
  AhcNode **e = ahc_env(2);
  e[0] = fd;
  e[1] = ahc_mk_int(POLLIN);
  return ahc_mk_fun(io_wait_fd, e);
}

static AhcNode *p_wait_write(AhcNode *fd) {
  AhcNode **e = ahc_env(2);
  e[0] = fd;
  e[1] = ahc_mk_int(POLLOUT);
  return ahc_mk_fun(io_wait_fd, e);
}

/* tryRecv: never parks. */
static AhcNode *io_try_recv(AhcNode **env, AhcNode *w) {
  AhcChan *c = chan_of(env[0]);
  (void)w;
  if (c->head) {
    AhcChanCell *cell = c->head;
    c->head = cell->next;
    if (!c->head) c->tail = NULL;
    return mk_just(cell->v);
  }
  return mk_nothing();
}

static AhcNode *p_try_recv(AhcNode *ci) {
  AhcNode **e = ahc_env(1);
  e[0] = ci;
  return ahc_mk_fun(io_try_recv, e);
}

/* selectRecv: first non-empty channel in LIST ORDER - the pinned
   tie-break; parks on all of them when every one is empty. */
static AhcNode *io_select_recv(AhcNode **env, AhcNode *w) {
  (void)w;
  for (;;) {
    AhcNode *cell = ahc_eval(env[0]);
    long idx = 0;
    while (cell->tag == AHC_CON && cell->u.con.contag == CONS_TAG) {
      AhcChan *c = chan_of(cell->u.con.fields[0]);
      if (c->head) {
        AhcChanCell *cc = c->head;
        c->head = cc->next;
        if (!c->head) c->tail = NULL;
        {
          AhcNode *pr = ahc_mk_con(1, 2);
          pr->u.con.fields[0] = ahc_mk_int(idx);
          pr->u.con.fields[1] = cc->v;
          return pr;
        }
      }
      cell = ahc_eval(cell->u.con.fields[1]);
      idx++;
    }
    if (idx == 0) ahc_die("selectRecv: empty channel list");
    cell = ahc_eval(env[0]);
    idx = 0;
    while (cell->tag == AHC_CON && cell->u.con.contag == CONS_TAG) {
      sel_enlist(chan_of(cell->u.con.fields[0]), cur_task, idx);
      cell = ahc_eval(cell->u.con.fields[1]);
      idx++;
    }
    park();
    cell = ahc_eval(env[0]);
    while (cell->tag == AHC_CON && cell->u.con.contag == CONS_TAG) {
      sel_unlink(chan_of(cell->u.con.fields[0]), cur_task);
      cell = ahc_eval(cell->u.con.fields[1]);
    }
    if (cur_task->xfer) {
      AhcNode *v = cur_task->xfer;
      AhcNode *pr = ahc_mk_con(1, 2);
      cur_task->xfer = NULL;
      pr->u.con.fields[0] = ahc_mk_int(cur_task->sel_index);
      pr->u.con.fields[1] = v;
      return pr;
    }
  }
}

static AhcNode *p_select_recv(AhcNode *cs) {
  AhcNode **e = ahc_env(1);
  e[0] = cs;
  return ahc_mk_fun(io_select_recv, e);
}

/* waitReadOr: a message beats a ready fd (the pre-park check);
   after the park, whichever event woke us decided - each wake path
   fires at most once (state==1 guards). The accept-loop shape. */
static AhcNode *io_wait_read_or(AhcNode **env, AhcNode *w) {
  long fd = ahc_eval(env[0])->u.i;
  AhcChan *c = chan_of(env[1]);
  (void)w;
  if (c->head) {
    AhcChanCell *cell = c->head;
    c->head = cell->next;
    if (!c->head) c->tail = NULL;
    return mk_just(cell->v);
  }
  sel_enlist(c, cur_task, 0);
  iow_add(cur_task, (int)fd, POLLIN);
  park();
  iow_remove(cur_task);
  sel_unlink(c, cur_task);
  if (cur_task->xfer) {
    AhcNode *v = cur_task->xfer;
    cur_task->xfer = NULL;
    return mk_just(v);
  }
  return mk_nothing();
}

static AhcNode *p_wait_read_or(AhcNode *fd, AhcNode *ci) {
  AhcNode **e = ahc_env(2);
  e[0] = fd;
  e[1] = ci;
  return ahc_mk_fun(io_wait_read_or, e);
}

/* ----- protected values (M103) -----------------------------------
   Ada's protected object, pure-transition edition (design note
   section 6): state + read (s -> a) + update (s -> (s, r)) +
   entry (barrier s -> Bool, then update). Operations are pure, so
   on one OS thread a protected action is atomic by construction.
   Updates commit the new state to WHNF INSIDE the action - that is
   where contract wrappers and refined-field checks fire, before
   any other task can observe the state. After every commit the
   epilogue rescans the entry queue FROM THE HEAD in arrival
   order (each enabled body is a fresh protected action, Ada's
   eggshell rule) - first-arrived, first-served, deterministic. */

typedef struct AhcProtWaiter {
  AhcNode *barrier, *body;
  AhcTask *task;
  struct AhcProtWaiter *next;
} AhcProtWaiter;

typedef struct AhcProt {
  AhcNode *state;
  AhcProtWaiter *waiters;      /* entry queue, FIFO */
} AhcProt;

static AhcProt **prot_reg;  static int prot_n, prot_cap;

static AhcProt *prot_of(AhcNode *n) {
  long i = ahc_eval(n)->u.i;
  if (i < 0 || i >= prot_n || !prot_reg[i])
    ahc_die("protected value does not exist");
  return prot_reg[i];
}

/* Run one update body against the current state and commit.
   Both evals happen BEFORE either store, so a death (contract
   violation, refined-field check) leaves the old state intact. */
static AhcNode *prot_commit(AhcProt *p, AhcNode *body) {
  AhcNode *pair = ahc_eval(ahc_apply(body, p->state));
  AhcNode *ns;
  if (pair->tag != AHC_CON || pair->u.con.arity != 2)
    ahc_die("protected update returned a non-pair");
  ns = ahc_eval(pair->u.con.fields[0]);
  p->state = ns;
  return pair->u.con.fields[1];
}

static int prot_barrier_holds(AhcProt *p, AhcNode *barrier) {
  return ahc_eval(ahc_apply(barrier, p->state))->u.con.contag == 2;
}

static void prot_epilogue(AhcProt *p) {
  int progressed = 1;
  while (progressed) {
    AhcProtWaiter **link = &p->waiters;
    progressed = 0;
    while (*link) {
      AhcProtWaiter *w = *link;
      if (w->task->state >= 2) {     /* died while parked */
        *link = w->next;
        continue;
      }
      if (prot_barrier_holds(p, w->barrier)) {
        *link = w->next;
        w->task->xfer = prot_commit(p, w->body);
        wake(w->task);
        progressed = 1;              /* state changed: rescan */
        break;
      }
      link = &w->next;
    }
  }
}

static AhcNode *io_prot_new(AhcNode **env, AhcNode *w) {
  AhcProt *p = (AhcProt *)AHC_ALLOC(sizeof(AhcProt));
  (void)w;
  if (!p) ahc_die("out of memory");
  p->state = ahc_eval(env[0]);   /* WHNF from birth (section 6.3) */
  p->waiters = NULL;
  return ahc_mk_int(reg_add((void ***)&prot_reg,
                            &prot_n, &prot_cap, p));
}

static AhcNode *p_prot_new(AhcNode *s) {
  AhcNode **e = ahc_env(1);
  e[0] = s;
  return ahc_mk_fun(io_prot_new, e);
}

/* reading: an observation-consistent snapshot - the projection is
   applied to the state AS OF the action and forced only as far as
   the caller demands. */
static AhcNode *io_prot_read(AhcNode **env, AhcNode *w) {
  AhcProt *p = prot_of(env[0]);
  (void)w;
  return ahc_apply(env[1], p->state);
}

static AhcNode *p_prot_read(AhcNode *pi, AhcNode *f) {
  AhcNode **e = ahc_env(2);
  e[0] = pi;
  e[1] = f;
  return ahc_mk_fun(io_prot_read, e);
}

static AhcNode *io_prot_update(AhcNode **env, AhcNode *w) {
  AhcProt *p = prot_of(env[0]);
  AhcNode *r;
  (void)w;
  r = prot_commit(p, env[1]);
  prot_epilogue(p);
  return r;
}

static AhcNode *p_prot_update(AhcNode *pi, AhcNode *f) {
  AhcNode **e = ahc_env(2);
  e[0] = pi;
  e[1] = f;
  return ahc_mk_fun(io_prot_update, e);
}

static AhcNode *io_prot_entry(AhcNode **env, AhcNode *w) {
  AhcProt *p = prot_of(env[0]);
  (void)w;
  if (prot_barrier_holds(p, env[1])) {
    AhcNode *r = prot_commit(p, env[2]);
    prot_epilogue(p);
    return r;
  }
  {
    AhcProtWaiter *nw =
      (AhcProtWaiter *)AHC_ALLOC(sizeof(AhcProtWaiter));
    AhcProtWaiter **link = &p->waiters;
    if (!nw) ahc_die("out of memory");
    nw->barrier = env[1];
    nw->body = env[2];
    nw->task = cur_task;
    nw->next = NULL;
    while (*link) link = &(*link)->next;
    *link = nw;
  }
  park();                    /* the epilogue ran our body for us */
  {
    AhcNode *r = cur_task->xfer;
    cur_task->xfer = NULL;
    return r;
  }
}

static AhcNode *p_prot_entry(AhcNode *pi, AhcNode *g, AhcNode *f) {
  AhcNode **e = ahc_env(3);
  e[0] = pi;
  e[1] = g;
  e[2] = f;
  return ahc_mk_fun(io_prot_entry, e);
}

/* ----- sparks (B1: par/pseq, design note 7.1/7.4) ----------------
   Worker OS threads evaluate PURE thunks only; every IO action
   still runs on the main thread under the Phase A scheduler, so
   results are identical by purity and the IO schedule identical by
   construction - B1 trades nothing observable and ships on by
   default. The pool starts lazily on the first `par`, so programs
   that never spark never see a second thread.

   Sparks live in per-thread bounded Chase-Lev deques (Le et al.'s
   weak-memory version): the owner pushes and pops its bottom,
   thieves CAS the top. A full deque DROPS the spark (counted) -
   sparks are advisory, the demander evaluates the thunk anyway.
   An `error` inside sparked pure code cannot be raised on the
   worker (that would make the failure time racy): the worker
   catches it and updates the thunk with a thunk that re-raises,
   so the message surfaces exactly when the main program demands
   the value - same bytes, same point, every run. */

#define AHC_MAX_WORKERS 32
#define SPARK_CAP 8192
/* Workers evaluate the same lazily-built structures main does, so
   they get main's stack budget (the 512MB trick, pthread edition;
   virtual, committed lazily). 64MB was tried and a 200k-cons
   forceList genuinely exhausted it. */
#define AHC_WORKER_STACK (512ul * 1024 * 1024)

typedef struct {
  long top, bottom;              /* __atomic-accessed */
  AhcNode *ring[SPARK_CAP];
} SparkDeque;

static SparkDeque spark_deques[AHC_MAX_WORKERS + 1];
static __thread int my_deque;    /* 0 = main thread */

#if defined(AHC_USE_BOEHM) || defined(AHC_GC_OWN)
int ahc_bump_slot_hint(void) { return my_deque; }
#endif
static AhcTask worker_shells[AHC_MAX_WORKERS];
#ifdef AHC_GC_OWN
static char *worker_stack_top[AHC_MAX_WORKERS];
static char *worker_parked_sp[AHC_MAX_WORKERS];
static OwnBlock
  *gc_pub_active[AHC_MAX_WORKERS + 1][3][OWN_NCLASS];
#endif
static pthread_mutex_t idle_mx = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t idle_cv = PTHREAD_COND_INITIALIZER;
static long sparks_created, sparks_converted, sparks_fizzled,
  sparks_dropped;                /* __atomic counters */

static void spark_push(SparkDeque *d, AhcNode *x) {
  long b = __atomic_load_n(&d->bottom, __ATOMIC_RELAXED);
  long t = __atomic_load_n(&d->top, __ATOMIC_ACQUIRE);
  if (b - t >= SPARK_CAP - 1) {
    __atomic_fetch_add(&sparks_dropped, 1, __ATOMIC_RELAXED);
    return;
  }
  d->ring[b % SPARK_CAP] = x;
  __atomic_store_n(&d->bottom, b + 1, __ATOMIC_RELEASE);
}

static AhcNode *spark_pop(SparkDeque *d) {   /* owner, bottom end */
  long b = __atomic_load_n(&d->bottom, __ATOMIC_RELAXED) - 1;
  AhcNode *x;
  long t;
  __atomic_store_n(&d->bottom, b, __ATOMIC_RELAXED);
  __atomic_thread_fence(__ATOMIC_SEQ_CST);
  t = __atomic_load_n(&d->top, __ATOMIC_RELAXED);
  if (t <= b) {
    x = d->ring[b % SPARK_CAP];
    if (t == b) {
      if (!__atomic_compare_exchange_n(&d->top, &t, t + 1, 0,
                                       __ATOMIC_SEQ_CST,
                                       __ATOMIC_RELAXED))
        x = NULL;
      __atomic_store_n(&d->bottom, b + 1, __ATOMIC_RELAXED);
    }
  } else {
    x = NULL;
    __atomic_store_n(&d->bottom, b + 1, __ATOMIC_RELAXED);
  }
  return x;
}

static AhcNode *spark_steal(SparkDeque *d) {  /* thief, top end */
  long t = __atomic_load_n(&d->top, __ATOMIC_ACQUIRE);
  long b;
  AhcNode *x;
  __atomic_thread_fence(__ATOMIC_SEQ_CST);
  b = __atomic_load_n(&d->bottom, __ATOMIC_ACQUIRE);
  if (t >= b) return NULL;
  x = d->ring[t % SPARK_CAP];
  if (!__atomic_compare_exchange_n(&d->top, &t, t + 1, 0,
                                   __ATOMIC_SEQ_CST,
                                   __ATOMIC_RELAXED))
    return NULL;
  return x;
}

/* The value a sparked error becomes: a thunk that re-raises the
   original message when the program actually demands it. */
static AhcNode *sparked_die_code(AhcNode **env) {
  fflush(stdout);   /* p_error's invariant: produced output
                       precedes the die, worker path included */
  ahc_die((const char *)env[0]->u.p);
  return NULL;
}

static AhcNode *mk_sparked_die(const char *msg) {
  size_t l = strlen(msg);
  char *m = (char *)AHC_ALLOC(l + 1);
  AhcNode *pn;
  AhcNode **e;
  if (!m) ahc_die("out of memory");
  memcpy(m, msg, l + 1);
  pn = ahc_mk_ptr(m);          /* child BEFORE owner (invariant) */
  e = ahc_env(1);
  e[0] = pn;
  return ahc_mk_thunk(sparked_die_code, e);
}

/* Evaluate one spark. Try-claim: if the thunk is already claimed
   or evaluated, the spark fizzled and the worker moves on - a
   worker never spins on a WHOLE spark, only on nested blackholes
   inside one it owns (ahc_eval's rule). */
static void run_spark(AhcNode *x) {
  AhcCode code;
  AhcNode **env;
  AhcTag expect = AHC_THUNK;
  if (!__atomic_compare_exchange_n(&x->tag, &expect, AHC_CLAIM, 0,
                                   __ATOMIC_ACQ_REL,
                                   __ATOMIC_ACQUIRE)) {
    __atomic_fetch_add(&sparks_fizzled, 1, __ATOMIC_RELAXED);
    return;
  }
  code = x->u.thunk.code;     /* safe only post-claim, as in eval */
  env = x->u.thunk.env;
  __atomic_store_n(&x->u.bh.owner, cur_task, __ATOMIC_RELAXED);
  x->u.bh.waiters = NULL;
  __atomic_store_n(&x->tag, AHC_BLACKHOLE, __ATOMIC_RELEASE);
  {
    AhcNode *v;
    if (setjmp(*ahc_err_frame()) == 0) {
      v = ahc_eval(code(env));
      ahc_err_disarm();
    } else {
      v = mk_sparked_die(cur_task->err_msg);
    }
    __atomic_store_n(&x->u.ind, v, __ATOMIC_RELEASE);
    __atomic_store_n(&x->tag, AHC_IND, __ATOMIC_RELEASE);
#ifdef AHC_GC_OWN
    own_write_barrier(x);
#endif
  }
  __atomic_fetch_add(&sparks_converted, 1, __ATOMIC_RELAXED);
}

static void *worker_main(void *arg) {
  int me = (int)(intptr_t)arg;
  cur_task = &worker_shells[me];
  my_deque = me + 1;
#ifdef AHC_GC_OWN
  worker_stack_top[me] =
    (char *)pthread_get_stackaddr_np(pthread_self());
#endif
  for (;;) {
    AhcNode *x;
#ifdef AHC_GC_OWN
    own_safepoint();
#endif
    x = spark_pop(&spark_deques[my_deque]);
    if (!x) {
      int v;
      for (v = 0; v <= n_workers && !x; v++)
        if (v != my_deque) x = spark_steal(&spark_deques[v]);
    }
    if (x) {
      run_spark(x);
    } else {
      /* 1ms naps instead of a wake protocol: robust against lost
         wakeups by construction, and the idle cost is noise.
         Plain POSIX pthread_cond_timedwait with an ABSOLUTE
         deadline - the relative _np variant used here until M116
         is Darwin-only and silently made the whole runtime
         non-portable, which nobody noticed because CI is parked. */
      struct timespec ts;
      pthread_mutex_lock(&idle_mx);
      clock_gettime(CLOCK_REALTIME, &ts);
      ts.tv_nsec += 1000000;
      if (ts.tv_nsec >= 1000000000L) {
        ts.tv_nsec -= 1000000000L;
        ts.tv_sec += 1;
      }
      pthread_cond_timedwait(&idle_cv, &idle_mx, &ts);
      pthread_mutex_unlock(&idle_mx);
    }
  }
  return NULL;
}

static pthread_once_t workers_once = PTHREAD_ONCE_INIT;

static void start_workers(void) {
  /* OPT-IN (AHC_WORKERS=N), not default-on as section 7.1 first
     planned: the machinery scales (plain-malloc control: 2.96x on
     8 workers), but under the shipped collector - every Boehm
     configuration measured, including a thread-local-alloc source
     build with collections disabled - parallel mutators LOSE
     time, so the honest default is off until the collector
     campaign (design note 7.6, the gate's return clause). */
  const char *cfg = getenv("AHC_WORKERS");
#ifdef AHC_GC_OWN
  /* C3 flips the default ON for the own collector: the B1 gate
     is re-run against an allocator that can feed the workers. */
  long ncpu = sysconf(_SC_NPROCESSORS_ONLN);
  long want = cfg ? atol(cfg)
                  : (ncpu > 1 ? (ncpu - 1 < 4 ? ncpu - 1 : 4) : 0);
#else
  long want = cfg ? atol(cfg) : 0;
#endif
  int i;
  if (want < 0) want = 0;
  if (want > AHC_MAX_WORKERS) want = AHC_MAX_WORKERS;
  for (i = 0; i < want; i++) {
    pthread_t tid;
    pthread_attr_t at;
    worker_shells[i].is_worker = 1;
    worker_shells[i].id = -(i + 1);
    pthread_attr_init(&at);
    pthread_attr_setstacksize(&at, AHC_WORKER_STACK);
    if (pthread_create(&tid, &at, worker_main,
                       (void *)(intptr_t)i) != 0)
      break;                    /* keep however many started */
    pthread_attr_destroy(&at);
    /* visible to stealers as they come */
    __atomic_store_n(&n_workers, i + 1, __ATOMIC_RELEASE);
  }
}

/* Everything needed to tell the candidate explanations apart when
   the spin watchdog fires: who owns the node we are stuck on, what
   that owner is doing, whether a collection is mid-rendezvous, and
   whether any spark work is still outstanding. */
/* Name a tag for the report. The report re-loads the tag, so it can
   legitimately differ from the one that triggered the trip - a node
   that reached IND by the time we print says the spin was resolving,
   which is itself the answer. */
static const char *ahc_tag_name(int t) {
  switch (t) {
  case AHC_IND:       return "IND";
  case AHC_THUNK:     return "THUNK";
  case AHC_CLAIM:     return "CLAIM";
  case AHC_BLACKHOLE: return "BLACKHOLE";
  default:            return "other/whnf";
  }
}

static void ahc_spin_report(AhcNode *n, void *owner, AhcTask *self) {
  int i, nw = __atomic_load_n(&n_workers, __ATOMIC_RELAXED);
  char who[64];
  char me[64];
  /* owner shares its union slot with the payload, so identify it by
     COMPARING against known task addresses - never by dereference. */
  snprintf(who, sizeof who, "UNRECOGNISED (stale payload word?)");
  if (owner == (void *)&main_task) snprintf(who, sizeof who, "main_task");
  else if (owner == (void *)self)
    snprintf(who, sizeof who, "SELF (should have been <<loop>>)");
  else {
    int found = 0;
    for (i = 0; i < AHC_MAX_WORKERS && !found; i++)
      if (owner == (void *)&worker_shells[i]) {
        snprintf(who, sizeof who, "worker #%d", i);
        found = 1;
      }
    for (i = 0; i < task_n && !found; i++)
      if (task_reg[i] && owner == (void *)task_reg[i]) {
        snprintf(who, sizeof who, "green task #%d", i);
        found = 1;
      }
  }
  if (self == &main_task) snprintf(me, sizeof me, "main_task");
  else if (self->is_worker) {
    snprintf(me, sizeof me, "a worker");
    for (i = 0; i < AHC_MAX_WORKERS; i++)
      if (self == &worker_shells[i]) {
        snprintf(me, sizeof me, "worker #%d", i);
        break;
      }
  } else snprintf(me, sizeof me, "a green task");
  fprintf(stderr,
          "\n=== SPIN WATCHDOG ===\n"
          "node %p tag=%s\nowner=%p -> %s\nself=%p -> %s\n",
          (void *)n,
          ahc_tag_name((int)__atomic_load_n(&n->tag, __ATOMIC_ACQUIRE)),
          owner, who, (void *)self, me);
#ifdef AHC_GC_OWN
  fprintf(stderr, "gc: collections=%ld  (rendezvous state below)\n",
          own_gc_count);
  ahc_spin_report_gc(nw);
#endif
  fprintf(stderr, "sparks: created %ld converted %ld fizzled %ld\n",
          __atomic_load_n(&sparks_created, __ATOMIC_RELAXED),
          __atomic_load_n(&sparks_converted, __ATOMIC_RELAXED),
          __atomic_load_n(&sparks_fizzled, __ATOMIC_RELAXED));
  for (i = 0; i <= nw && i <= AHC_MAX_WORKERS; i++) {
    SparkDeque *d = &spark_deques[i];
    long t = __atomic_load_n(&d->top, __ATOMIC_RELAXED);
    long b = __atomic_load_n(&d->bottom, __ATOMIC_RELAXED);
    fprintf(stderr, "  deque[%d] top=%ld bottom=%ld pending=%ld\n",
            i, t, b, b - t);
  }
  for (i = 0; i < nw && i < AHC_MAX_WORKERS; i++)
    fprintf(stderr, "  worker[%d] addr=%p state=%d\n",
            i, (void *)&worker_shells[i], worker_shells[i].state);
  fprintf(stderr, "=== END ===\n");
}

static void spark_stats(void) {
  fprintf(stderr,
          "sparks: created %ld converted %ld fizzled %ld dropped %ld\n",
          __atomic_load_n(&sparks_created, __ATOMIC_RELAXED),
          __atomic_load_n(&sparks_converted, __ATOMIC_RELAXED),
          __atomic_load_n(&sparks_fizzled, __ATOMIC_RELAXED),
          __atomic_load_n(&sparks_dropped, __ATOMIC_RELAXED));
}

static AhcNode *p_par(AhcNode *a, AhcNode *b) {
  pthread_once(&workers_once, start_workers);
  if (n_workers > 0
      && __atomic_load_n(&a->tag, __ATOMIC_ACQUIRE) == AHC_THUNK) {
    spark_push(&spark_deques[my_deque], a);
    __atomic_fetch_add(&sparks_created, 1, __ATOMIC_RELAXED);
    pthread_cond_signal(&idle_cv);
  }
  return b;
}

/* seq with a guaranteed order: the left argument first. */
static AhcNode *p_pseq(AhcNode *a, AhcNode *b) {
  ahc_eval(a);
  return b;
}

#ifdef AHC_GC_OWN
/* ----- the own collector, stage C2: STW mark-sweep ---------------
   collector-design-note.md sections 2 and 4. The world is main
   plus the B1 workers; rendezvous is cooperative at three
   safepoint families - the allocation slow path (every 64KB of
   allocation), blackhole spins, and the worker loop top - so a
   worker is caught within one block of allocation or one spin
   iteration. Only the main OS thread triggers and runs the
   collection, which keeps determinism trivially: a pause is
   invisible to the green scheduler's switch points.

   Roots: every thread stack's live extent (conservatively,
   through the block-table filter), the executable's data segment
   (conservatively - this covers the prim table, the registries,
   funptr slots, and every generated g_Module_* global with zero
   codegen changes; the note's precise root arrays are deferred to
   C3, recorded as an errata), and the spark deques. The heap
   itself is traced BY TAG - precisely - with misc-kind objects
   (runtime structs) scanned conservatively, exactly as Boehm
   scanned them.

   Sweep is block-grain: an unmarked block returns to the pool
   (zeroed on reuse - which also restores the allocation locality
   leak mode lost), a partly-live block is retired whole. */

#ifdef __APPLE__
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#endif

static int gc_want;                       /* atomic */
static int gc_parked;                     /* atomic */

static AhcNode **gc_mark_stack;
static size_t gc_msp, gc_mcap;

static int own_marked(void *o) {
  size_t i = (size_t)((char *)o - own_base) >> 3;
  return own_marks[i >> 3] & (unsigned char)(1u << (i & 7));
}

static void own_set_mark(void *o) {
  size_t i = (size_t)((char *)o - own_base) >> 3;
  own_marks[i >> 3] |= (unsigned char)(1u << (i & 7));
}

/* The conservative filter: any word -> object base, or NULL. */
static void *own_find_object(const void *cand, OwnBlock **bout) {
  char *c = (char *)cand;
  size_t bi;
  OwnBlock *b;
  if (c < own_base || c >= own_commit) return NULL;
  bi = (size_t)(c - own_base) / OWN_BLOCK;
  switch (own_bstate[bi]) {
  case OWN_B_SMALL: {
    size_t off, slot;
    b = (OwnBlock *)(own_base + bi * OWN_BLOCK);
    if (c < (char *)b + OWN_HDR) return NULL;
    off = (size_t)(c - ((char *)b + OWN_HDR));
    slot = off / b->size_class;
    off = OWN_HDR + slot * b->size_class;
    if (off + b->size_class > b->bump) return NULL;
    *bout = b;
    return (char *)b + off;
  }
  case OWN_B_LARGE_TAIL:
    while (own_bstate[bi] == OWN_B_LARGE_TAIL) bi--;
    /* fall through to the head */
  case OWN_B_LARGE_HEAD:
    b = (OwnBlock *)(own_base + bi * OWN_BLOCK);
    if (c >= (char *)b + OWN_HDR + b->size_class) return NULL;
    if (c < (char *)b + OWN_HDR) return NULL;
    *bout = b;
    return (char *)b + OWN_HDR;
  default:
    return NULL;
  }
}

static void gc_push(const void *cand) {
  OwnBlock *b;
  void *o = own_find_object(cand, &b);
  if (!o || own_marked(o)) return;
  own_set_mark(o);
  if (gc_msp == gc_mcap) {
    gc_mcap = gc_mcap ? gc_mcap * 2 : 65536;
    gc_mark_stack = (AhcNode **)realloc(gc_mark_stack,
                                        gc_mcap * sizeof(void *));
    if (!gc_mark_stack) ahc_die("own gc: mark stack exhausted");
  }
  gc_mark_stack[gc_msp++] = (AhcNode *)o;
}

static void gc_scan_range(const char *lo, const char *hi) {
  const char *p =
    (const char *)(((uintptr_t)lo + 7) & ~(uintptr_t)7);
  for (; p + sizeof(void *) <= hi; p += sizeof(void *))
    gc_push(*(void *const *)p);
}

static void gc_trace(AhcNode *o) {
  OwnBlock *b;
  void *base = own_find_object(o, &b);
  size_t sz;
  (void)base;
  sz = b->size_class;
  if (b->kind == 0) {                     /* a node: by tag */
    switch (o->tag) {
    case AHC_THUNK:
    case AHC_CLAIM:                       /* env still in place */
      gc_push(o->u.thunk.env);
      break;
    case AHC_FUN:
      gc_push(o->u.fun.env);
      break;
    case AHC_CON:
      gc_push(o->u.con.fields);
      break;
    case AHC_IND:
      gc_push(o->u.ind);
      break;
    case AHC_BLACKHOLE:
      gc_push(o->u.bh.owner);            /* a task struct, or */
      gc_push(o->u.bh.waiters);          /* static - filtered */
      break;
    case AHC_BIGINT:
      gc_push(o->u.big.d);
      break;
    default:                              /* INT DOUBLE CHAR PTR */
      break;
    }
  } else {
    /* ptr-array: homogeneous node pointers; misc: conservative.
       Either way every word goes through the filter. */
    gc_scan_range((const char *)o, (const char *)o + sz);
  }
}

/* Bounded runtime structures are re-walked every collection
   instead of barriered: tasks, scopes, protected values, channel
   HEADS (cell chains are covered by the tail-append barrier).
   They mutate constantly and their population is small - this is
   the remembered set for everything that is not the pure graph. */
static void gc_walk_runtime(void) {
  int i;
  for (i = 0; i < task_n; i++)
    if (task_reg[i])
      gc_scan_range((const char *)task_reg[i],
                    (const char *)task_reg[i] + sizeof(AhcTask));
  gc_scan_range((const char *)&main_task,
                (const char *)(&main_task + 1));
  for (i = 0; i < scope_n; i++)
    if (scope_reg[i]) {
      AhcScope *sc = scope_reg[i];
      gc_scan_range((const char *)sc, (const char *)(sc + 1));
      if (sc->kids)
        gc_scan_range((const char *)sc->kids,
                      (const char *)(sc->kids + sc->n));
    }
  for (i = 0; i < chan_n; i++)
    if (chan_reg[i])
      gc_scan_range((const char *)chan_reg[i],
                    (const char *)(chan_reg[i] + 1));
  for (i = 0; i < prot_n; i++)
    if (prot_reg[i]) {
      AhcProt *pr = prot_reg[i];
      AhcProtWaiter *w;
      gc_scan_range((const char *)pr, (const char *)(pr + 1));
      for (w = pr->waiters; w; w = w->next)
        gc_scan_range((const char *)w, (const char *)(w + 1));
    }
}

/* Drain the remembered set: entries are OLD objects whose edges
   changed; trace them directly (gc_push would skip their sticky
   marks). */
static void gc_drain_remembered(void) {
  int s;
  size_t i;
  for (s = 0; s < AHC_OWN_NSLOTS; s++) {
    for (i = 0; i < own_ssb_n[s]; i++)
      gc_trace((AhcNode *)((void **)own_ssb_seg[s])[i]);
    own_ssb_n[s] = 0;
  }
}

static void gc_mark_from_roots(int nw) {
  int i;
  jmp_buf jb;
  setjmp(jb);                             /* spill my registers */
  /* my own stack (main OS thread; possibly a green task's). The
     floor is the spill buffer itself: register-held node pointers
     land in jb, and jb must be inside the scanned range - a
     worker-soak corruption taught this the hard way. */
  gc_scan_range((const char *)&jb, cur_task->stack_top);
  if (cur_task != &main_task && main_task.state < 2)
    gc_scan_range(main_task.parked_lo, main_task.stack_top);
  /* parked green tasks */
  for (i = 0; i < task_n; i++) {
    AhcTask *t = task_reg[i];
    if (t && t != cur_task && t->state < 2 && t->parked_lo)
      gc_scan_range(t->parked_lo, t->stack_top);
  }
  /* worker stacks, extents published at the rendezvous */
  for (i = 0; i < nw; i++)
    gc_scan_range(worker_parked_sp[i], worker_stack_top[i]);
  /* the executable's data segment: prims, registries, funptr
     slots, every generated g_Module_* - one conservative sweep */
  {
#ifdef __APPLE__
    unsigned long sz = 0;
    uint8_t *d = getsegmentdata(
      (const struct mach_header_64 *)_dyld_get_image_header(0),
      "__DATA", &sz);
    if (d) gc_scan_range((const char *)d, (const char *)d + sz);
#else
    extern char __data_start[], _end[];
    gc_scan_range(__data_start, _end);
#endif
  }
  /* in-flight sparks */
  for (i = 0; i <= nw; i++) {
    SparkDeque *d = &spark_deques[i];
    long t = __atomic_load_n(&d->top, __ATOMIC_RELAXED);
    long bt = __atomic_load_n(&d->bottom, __ATOMIC_RELAXED);
    for (; t < bt; t++) gc_push(d->ring[t % SPARK_CAP]);
  }
  while (gc_msp > 0) gc_trace(gc_mark_stack[--gc_msp]);
}

static long gc_sweep(int major) {
  size_t nblocks = (size_t)(own_commit - own_base) / OWN_BLOCK;
  size_t bi;
  long live = 0;
  int k, c, w;
  /* flag the blocks threads are actively bumping; they also stay
     dirty (their bumps continue into the next cycle) */
  for (w = 0; w <= AHC_MAX_WORKERS; w++)
    for (k = 0; k < 3; k++)
      for (c = 0; c < OWN_NCLASS; c++)
        if (gc_pub_active[w][k][c]) {
          gc_pub_active[w][k][c]->gc_active = 1;
          gc_pub_active[w][k][c]->epoch = (uint32_t)own_gc_count;
        }
  for (bi = 0; bi < nblocks; bi++) {
    OwnBlock *b = (OwnBlock *)(own_base + bi * OWN_BLOCK);
    switch (own_bstate[bi]) {
    case OWN_B_SMALL: {
      uint32_t off, sc = b->size_class;
      uint32_t nlive = 0, nfree = 0;
      /* minor: only DIRTY blocks (allocated into this cycle) are
         swept; everything else keeps its sticky marks and its
         standing free list. Marks are never cleared here - the
         next major clears the whole bitmap before it marks. */
      if (!major && b->epoch != (uint32_t)own_gc_count) {
        live += OWN_BLOCK;
        break;
      }
      /* Fast path: the block's mark bits live in one contiguous
         1KB bitmap slice. If every word is zero the whole block
         is garbage - free it without touching a single slot. On
         high-churn/low-survival programs (parfib retains ~0) this
         is nearly every block, and it turns the sweep from
         O(slots) into O(block/512). */
      {
        size_t mlo = (bi * OWN_BLOCK) >> 6;
        size_t mhi = ((bi + 1) * OWN_BLOCK) >> 6;
        const uint64_t *mw = (const uint64_t *)(own_marks + mlo);
        size_t nw = (mhi - mlo) / 8, wi;
        int any = 0;
        for (wi = 0; wi < nw && !any; wi++)
          if (mw[wi]) any = 1;
        if (!any && !b->gc_active) {
          own_bstate[bi] = OWN_B_FREE;
          b->free_head = NULL;
          b->free_count = 0;
          b->next =
            (OwnBlock *)__atomic_load_n(&own_pool, __ATOMIC_RELAXED);
          __atomic_store_n(&own_pool, b, __ATOMIC_RELAXED);
#ifdef MADV_FREE_REUSABLE
          if (own_madvise)
            madvise((char *)b + OWN_HDR, OWN_BLOCK - OWN_HDR,
                    MADV_FREE_REUSABLE);
#endif
          break;
        }
      }
      b->free_head = NULL;
      for (off = OWN_HDR; off + sc <= b->bump; off += sc) {
        char *o = (char *)b + off;
        if (own_marked(o)) {
          nlive++;
        } else {
          *(void **)o = b->free_head;   /* chain through the slot */
          b->free_head = o;
          nfree++;
        }
      }
      b->free_count = nfree;
      if (nlive == 0 && !b->gc_active) {
        own_bstate[bi] = OWN_B_FREE;
        b->free_head = NULL;
        b->next =
          (OwnBlock *)__atomic_load_n(&own_pool, __ATOMIC_RELAXED);
        __atomic_store_n(&own_pool, b, __ATOMIC_RELAXED);
#ifdef MADV_FREE_REUSABLE
        /* Handing pages back costs a SYSCALL PER BLOCK, and the
           C4 profile priced it at 24% of parfib's wall time
           (4.72s -> 3.58s without). It buys RSS on block-churning
           programs, so it stays - as an opt-in knob, off by
           default, throughput first. */
        if (own_madvise)
          madvise((char *)b + OWN_HDR, OWN_BLOCK - OWN_HDR,
                  MADV_FREE_REUSABLE);
#endif
      } else {
        live += (long)nlive * sc + OWN_HDR;
        if (nfree > 0 && !b->gc_active) {
          b->next = own_partial[b->kind][(sc >> 3) - 1];
          own_partial[b->kind][(sc >> 3) - 1] = b;
        }
      }
      break;
    }
    case OWN_B_LARGE_HEAD: {
      size_t nb = b->nblocks, j;
      void *obj = (char *)b + OWN_HDR;
      if (!major && b->epoch != (uint32_t)own_gc_count) {
        live += (long)(nb * OWN_BLOCK);   /* sticky: floats */
        bi += nb - 1;
        break;
      }
      if (own_marked(obj)) {
        live += (long)(nb * OWN_BLOCK);
      } else {
        for (j = 0; j < nb; j++) {
          OwnBlock *fb = (OwnBlock *)(own_base
                                      + (bi + j) * OWN_BLOCK);
          own_bstate[bi + j] = OWN_B_FREE;
          fb->next =
            (OwnBlock *)__atomic_load_n(&own_pool, __ATOMIC_RELAXED);
          __atomic_store_n(&own_pool, fb, __ATOMIC_RELAXED);
        }
      }
      bi += nb - 1;
      break;
    }
    default:
      break;
    }
  }
  for (w = 0; w <= AHC_MAX_WORKERS; w++)
    for (k = 0; k < 3; k++)
      for (c = 0; c < OWN_NCLASS; c++)
        if (gc_pub_active[w][k][c]) {
          gc_pub_active[w][k][c]->gc_active = 0;
          gc_pub_active[w][k][c] = NULL;
        }
  return live;
}

static unsigned char *own_shadow;   /* paranoid-mode bitmap */

static int shadow_marked(void *o) {
  size_t i = (size_t)((char *)o - own_base) >> 3;
  return own_shadow[i >> 3] & (unsigned char)(1u << (i & 7));
}

static void own_paranoid_check(int nw) {
  size_t bytes = ((size_t)(own_commit - own_base) / 64);
  size_t nblocks = (size_t)(own_commit - own_base) / OWN_BLOCK;
  size_t bi;
  unsigned char *real;
  if (!own_shadow)
    own_shadow = (unsigned char *)malloc(OWN_RESERVE / 64 / 16);
  /* swap: run a FULL mark into a fresh bitmap */
  real = own_marks;
  own_marks = own_shadow;
  memset(own_marks, 0, bytes);
  gc_walk_runtime();
  gc_mark_from_roots(nw);
  own_shadow = own_marks;
  own_marks = real;
  /* every shadow-live object in a DIRTY block must be really
     marked - those are the slots the minor sweep will free */
  for (bi = 0; bi < nblocks; bi++) {
    OwnBlock *b = (OwnBlock *)(own_base + bi * OWN_BLOCK);
    uint32_t off, sc;
    if (own_bstate[bi] != OWN_B_SMALL) continue;
    if (b->epoch != (uint32_t)own_gc_count) continue;
    sc = b->size_class;
    for (off = OWN_HDR; off + sc <= b->bump; off += sc) {
      char *o = (char *)b + off;
      if (shadow_marked(o) && !own_marked(o)) {
        fprintf(stderr,
                "own gc PARANOID: losing %p kind=%u sc=%u "
                "tag=%d epoch=%u gc=%ld\n",
                (void *)o, b->kind, sc,
                b->kind == 0 ? (int)((AhcNode *)o)->tag : -1,
                b->epoch, own_gc_count);
        /* AHC_OWN_PARANOID=2 additionally hunts referrers - an
           O(heap^2) scan that names the object holding the edge,
           which is what identifies the violating construction
           site. Worth every second when it is needed. */
        if (own_paranoid_level >= 2) {
          size_t bj;
          for (bj = 0; bj < nblocks; bj++) {
            OwnBlock *rb = (OwnBlock *)(own_base + bj * OWN_BLOCK);
            uint32_t roff, rsc;
            if (own_bstate[bj] != OWN_B_SMALL) continue;
            rsc = rb->size_class;
            for (roff = OWN_HDR; roff + rsc <= rb->bump;
                 roff += rsc) {
              char *r = (char *)rb + roff;
              size_t w;
              if (!shadow_marked(r)) continue;
              for (w = 0; w + 8 <= rsc; w += 8)
                if (*(void **)(r + w) == (void *)o) {
                  fprintf(stderr,
                          "  referrer %p kind=%u sc=%u tag=%d "
                          "marked=%d epoch=%u word=%zu\n",
                          (void *)r, rb->kind, rsc,
                          rb->kind == 0
                            ? (int)((AhcNode *)r)->tag : -1,
                          own_marked(r), rb->epoch, w / 8);
                }
            }
          }
        }
        ahc_die("own gc: generational invariant violated"
                " (see AHC_OWN_PARANOID output)");
      }
    }
  }
}

/* Mark-completeness check: the mark set must be CLOSED under the
   points-to relation. Any marked object holding a pointer to an
   unmarked heap object is a missed edge - which is precisely the
   bug class that lets the sweep reclaim live data. Reports the
   source's kind/tag and the target, then dies. AHC_OWN_VERIFY=1. */
static int own_verify;
static long own_verify_bad;

/* one edge: complain if src is marked and dst is an unmarked heap
   object */
static void own_vcheck(void *src, const char *what, void *dst) {
  OwnBlock *tb, *sb;
  void *t = own_find_object(dst, &tb);
  if (!t || own_marked(t)) return;
  if (own_verify_bad++ < 12) {
    own_find_object(src, &sb);
    fprintf(stderr,
            "own gc MISSED EDGE: %-11s src=%p kind=%u tag=%d"
            " -> dst=%p kind=%u tag=%d\n",
            what, src, sb ? sb->kind : 99,
            (sb && sb->kind == 0) ? (int)((AhcNode *)src)->tag : -1,
            t, tb->kind,
            tb->kind == 0 ? (int)((AhcNode *)t)->tag : -1);
  }
}

static void own_verify_closure(void) {
  size_t nblocks = (size_t)(own_commit - own_base) / OWN_BLOCK;
  size_t bi;
  own_verify_bad = 0;

  for (bi = 0; bi < nblocks; bi++) {
    OwnBlock *b = (OwnBlock *)(own_base + bi * OWN_BLOCK);
    uint32_t off, sc;
    if (own_bstate[bi] == OWN_B_LARGE_TAIL
        || own_bstate[bi] == OWN_B_FREE
        || own_bstate[bi] == OWN_B_VIRGIN) continue;
    if (own_bstate[bi] == OWN_B_LARGE_HEAD) {
      char *o = (char *)b + OWN_HDR;
      size_t w;
      if (own_marked(o))
        for (w = 0; w + 8 <= b->size_class; w += 8)
          own_vcheck(o, "large", *(void **)(o + w));
      bi += b->nblocks - 1;
      continue;
    }
    sc = b->size_class;
    for (off = OWN_HDR; off + sc <= b->bump; off += sc) {
      char *o = (char *)b + off;
      if (!own_marked(o)) continue;
      if (b->kind == 0) {
        AhcNode *n = (AhcNode *)o;
        switch (n->tag) {
        case AHC_THUNK: case AHC_CLAIM:
          own_vcheck(o, "thunk.env", n->u.thunk.env); break;
        case AHC_FUN:   own_vcheck(o, "fun.env", n->u.fun.env); break;
        case AHC_CON:   own_vcheck(o, "con.fields", n->u.con.fields); break;
        case AHC_IND:   own_vcheck(o, "ind", n->u.ind); break;
        case AHC_BLACKHOLE:
          own_vcheck(o, "bh.owner", n->u.bh.owner);
          own_vcheck(o, "bh.waiters", n->u.bh.waiters); break;
        case AHC_BIGINT: own_vcheck(o, "big.d", n->u.big.d); break;
        default: break;
        }
      } else {
        size_t w;
        for (w = 0; w + 8 <= sc; w += 8)
          own_vcheck(o, b->kind == 1 ? "ptrarr" : "misc", *(void **)(o + w));
      }
    }
  }
  if (own_verify_bad) {
    fprintf(stderr, "own gc: %ld missed edges at collection %ld\n",
            own_verify_bad, own_gc_count);
    ahc_die("own gc: mark set is not closed");
  }
}

void ahc_spin_report_gc(int nw) {
  fprintf(stderr, "  gc_want=%d gc_parked=%d of %d in_gc=%d\n",
          __atomic_load_n(&gc_want, __ATOMIC_ACQUIRE),
          __atomic_load_n(&gc_parked, __ATOMIC_ACQUIRE), nw, own_in_gc);
}

static void own_collect(int major) {
  int nw;
  unsigned long spins = 0;
  own_in_gc = 1;
  nw = __atomic_load_n(&n_workers, __ATOMIC_ACQUIRE);
  memcpy(gc_pub_active[0], own_active, sizeof own_active);
  {
    double t0 = own_now();
    __atomic_store_n(&gc_want, 1, __ATOMIC_RELEASE);
    while (__atomic_load_n(&gc_parked, __ATOMIC_ACQUIRE) != nw) {
      if ((spins++ & 4095) == 0) pthread_cond_broadcast(&idle_cv);
      spin_pause(&spins);
    }
    own_t_rendezvous += own_now() - t0;
  }
  {
    double t_mark0 = own_now();
  if (major) {
    /* the whole bitmap resets; every sticky mark is re-earned */
    size_t bytes = ((size_t)(own_commit - own_base) / 64);
    memset(own_marks, 0, bytes);
    {
      int s;
      for (s = 0; s < AHC_OWN_NSLOTS; s++) own_ssb_n[s] = 0;
    }
  } else {
    gc_drain_remembered();
  }
  gc_walk_runtime();
  gc_mark_from_roots(nw);
  own_t_mark += own_now() - t_mark0;
  }
  if (!major && own_paranoid_level) own_paranoid_check(nw);
  if (own_verify) own_verify_closure();
  /* pool/partial mutations always under own_mx - uncontended
     here (workers parked), but the uniform discipline is what
     TSan can verify */
  pthread_mutex_lock(&own_mx);
  if (major) memset(own_partial, 0, sizeof own_partial);
  memset(own_free_tls, 0, sizeof own_free_tls);   /* my own */
  {
    /* live is a MAJOR-only measurement: a minor counts undirty
       blocks wholesale, and letting that inflate own_live_bytes
       fed the trigger a runaway threshold (832MB committed on
       b_map before this line existed) */
    double t_sweep0 = own_now();
    long live = gc_sweep(major);
    own_t_sweep += own_now() - t_sweep0;
    if (major) own_live_bytes = live;
  }
  pthread_mutex_unlock(&own_mx);
  __atomic_store_n(&own_since_gc, 0, __ATOMIC_RELAXED);
  own_gc_count++;
  if (major) {
    own_minors_since_major = 0;
    own_live_at_major = own_live_bytes;
  } else {
    own_minors_since_major++;
    own_minor_count++;
  }
  __atomic_store_n(&gc_want, 0, __ATOMIC_RELEASE);
  while (__atomic_load_n(&gc_parked, __ATOMIC_ACQUIRE) != 0)
    spin_pause(&spins);
  own_in_gc = 0;
}

static void own_maybe_collect(void) {
  static long floor_bytes = -1;
  long thr;
  if (cur_task->is_worker || own_in_gc) return;  /* worker test
     FIRST: own_in_gc is main's private flag, and a worker reading
     it was TSan's first C2 finding */
  if (floor_bytes < 0) {
    /* AHC_OWN_MIN is a PER-ALLOCATOR budget, not a global one -
       see the scaling below. The soak harness sets it tiny to
       force collections constantly. */
    const char *e = getenv("AHC_OWN_MIN");
    floor_bytes = e ? atol(e) : (4l << 20);
    /* NO CLAMP TO OWN_CHUNK. There used to be one, raising any
       floor below the 16MB chunk size up to it - which tied the
       collection POLICY to an allocation IMPLEMENTATION detail,
       made the documented 12MB default really 16MB, and silently
       ignored every AHC_OWN_MIN below 16MB. That last part is how
       "the trigger floor is not the lever" got recorded as a
       measured fact in M113: the knob under test did nothing.
       A chunk is a unit of address space, not a unit of garbage. */
    if (floor_bytes < (long)OWN_BLOCK) floor_bytes = OWN_BLOCK;
  }
  /* GROWTH-AWARE TRIGGER (M119). Collection frequency is a budget
     PER ALLOCATING THREAD, not a global byte count. With N spark
     workers the heap fills N+1 times faster, so a global threshold
     silently multiplies the collection RATE - and every collection
     is a stop-the-world rendezvous that all N+1 threads pay for.
     That is measured, not assumed: dropping the global threshold
     from 16.8MB to 12MB cost 9.7% at four workers and only 1.9%
     sequentially (M118 section 17), because only parallel runs pay
     rendezvous frequency.

     Scaling by the allocator count keeps per-thread collection
     frequency constant as parallelism changes, which is what lets
     one policy serve both gates: a sequential small-heap program
     gets a small threshold (peak RSS stays near its live set,
     which C2 measures) while a parallel allocation-heavy program
     gets a proportionally larger one (workers keep running between
     pauses, which C3 measures). The two gates never wanted
     different CONSTANTS - they wanted the constant to mean
     per-thread rather than global.

     Workers only exist once a program calls `par`, so a purely
     sequential program sees exactly the base budget. */
  thr = floor_bytes
        * (1 + (long)__atomic_load_n(&n_workers, __ATOMIC_RELAXED));
  if (thr < own_live_bytes * 2) thr = own_live_bytes * 2;
  if (__atomic_load_n(&own_since_gc, __ATOMIC_RELAXED) < thr)
    return;
  /* a major when minors have piled up float, or live has grown
     well past the last major's baseline; minor otherwise */
  {
    static long major_every = -1;
    long base = own_live_at_major;
    if (major_every < 0) {
      const char *e = getenv("AHC_OWN_MAJOR_EVERY");
      major_every = e ? atol(e) : 4;
      if (major_every < 1) major_every = 1;
    }
    if (base < (24l << 20)) base = 24l << 20;
    own_collect(own_minors_since_major >= major_every
                || own_live_bytes > base * 3);
  }
}

/* Workers park here; called from the allocation slow path, the
   blackhole spin loop, and the worker loop top. */
static void own_safepoint(void) {
  if (!__atomic_load_n(&gc_want, __ATOMIC_ACQUIRE)) return;
  if (!cur_task->is_worker) return;       /* main runs the GC */
  {
    int me = -(cur_task->id) - 1;
    jmp_buf jb;
    setjmp(jb);                           /* registers -> stack */
    worker_parked_sp[me] = (char *)&jb - 256;
    memcpy(gc_pub_active[me + 1], own_active, sizeof own_active);
    __atomic_fetch_add(&gc_parked, 1, __ATOMIC_ACQ_REL);
    /* RAW pause here - spin_pause would call back into this
       function (it is a safepoint) and recurse the stack away */
    {
      unsigned long s = 0;
      while (__atomic_load_n(&gc_want, __ATOMIC_ACQUIRE)) {
#if defined(__x86_64__)
        __builtin_ia32_pause();
#endif
        if ((++s & 1023) == 0) sched_yield();
      }
    }
    /* the sweep re-chained every free slot: stale lists dangle */
    memset(own_free_tls, 0, sizeof own_free_tls);
    __atomic_fetch_sub(&gc_parked, 1, __ATOMIC_ACQ_REL);
  }
}
#else
/* Boehm / no-GC builds: the hooks cost nothing. */
#endif

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

/* ----- Foreign.Marshal surface: raw memory for C interop.
   peek/poke move PRIMITIVE values only - this memory is malloc'd
   and never scanned by the collector, so node pointers must not be
   stored in it. Offsets are in bytes. -------------------------- */

static void *marshal_ptr(AhcNode *p, const char *what) {
  AhcNode *e = ahc_eval(p);
  if (e->tag != AHC_PTR || !e->u.p) {
    char eb[64];
    snprintf(eb, sizeof eb, "%s: NULL pointer", what);
    ahc_die(eb);
  }
  return e->u.p;
}

static AhcNode *io_malloc_bytes(AhcNode **env, AhcNode *w) {
  AhcNode *n = ahc_eval(env[0]);
  void *p;
  (void)w;
  if (n->tag != AHC_INT || n->u.i < 0)
    ahc_die("mallocBytes: bad size");
  p = malloc(n->u.i == 0 ? 1 : (size_t)n->u.i);
  if (!p) ahc_die("mallocBytes: out of memory");
  return ahc_mk_ptr(p);
}

static AhcNode *p_malloc_bytes(AhcNode *n) {
  AhcNode **e = ahc_env(1);
  e[0] = n;
  return ahc_mk_fun(io_malloc_bytes, e);
}

static AhcNode *io_free_ptr(AhcNode **env, AhcNode *w) {
  AhcNode *e = ahc_eval(env[0]);
  (void)w;
  if (e->tag == AHC_PTR && e->u.p) free(e->u.p);
  return ahc_mk_con(UNIT_TAG, 0);
}

static AhcNode *p_free_ptr(AhcNode *p) {
  AhcNode **e = ahc_env(1);
  e[0] = p;
  return ahc_mk_fun(io_free_ptr, e);
}

static AhcNode *p_plus_ptr(AhcNode *p, AhcNode *n) {
  AhcNode *e = ahc_eval(p);
  AhcNode *o = ahc_eval(n);
  if (o->tag != AHC_INT) ahc_die("plusPtr: offset out of range");
  return ahc_mk_ptr((char *)e->u.p + o->u.i);
}

static AhcNode *p_cast_ptr(AhcNode *p) {
  return p;
}

#define DEF_PEEK(SUF, TY, BOX) \
static AhcNode *io_peek_##SUF(AhcNode **env, AhcNode *w) { \
  char *p = (char *)marshal_ptr(env[0], "peek"); \
  long off = ahc_eval(env[1])->u.i; \
  TY v; \
  (void)w; \
  memcpy(&v, p + off, sizeof v); \
  return BOX; \
} \
static AhcNode *p_peek_##SUF(AhcNode *p, AhcNode *o) { \
  AhcNode **e = ahc_env(2); \
  e[0] = p; e[1] = o; \
  return ahc_mk_fun(io_peek_##SUF, e); \
}

DEF_PEEK(i8,  int8_t,   ahc_mk_int((long)v))
DEF_PEEK(i16, int16_t,  ahc_mk_int((long)v))
DEF_PEEK(i32, int32_t,  ahc_mk_int((long)v))
DEF_PEEK(i64, int64_t,  ahc_mk_int((long)v))
DEF_PEEK(u8,  uint8_t,  ahc_mk_int((long)v))
DEF_PEEK(u16, uint16_t, ahc_mk_int((long)v))
DEF_PEEK(u32, uint32_t, ahc_mk_int((long)v))
DEF_PEEK(u64, uint64_t, ahc_mk_ulong(v))
DEF_PEEK(d,   double,   ahc_mk_double(v))
DEF_PEEK(p,   void *,   ahc_mk_ptr(v))

#define DEF_POKE_INT(SUF, TY, BAD) \
static AhcNode *io_poke_##SUF(AhcNode **env, AhcNode *w) { \
  char *p = (char *)marshal_ptr(env[0], "poke"); \
  long off = ahc_eval(env[1])->u.i; \
  AhcNode *xv = ahc_eval(env[2]); \
  long x; \
  TY v; \
  (void)w; \
  if (xv->tag != AHC_INT) ahc_die("poke: value out of range"); \
  x = xv->u.i; \
  if (BAD) ahc_die("poke: value out of range"); \
  v = (TY)x; \
  memcpy(p + off, &v, sizeof v); \
  return ahc_mk_con(UNIT_TAG, 0); \
} \
static AhcNode *p_poke_##SUF(AhcNode *p, AhcNode *o, AhcNode *x) { \
  AhcNode **e = ahc_env(3); \
  e[0] = p; e[1] = o; e[2] = x; \
  return ahc_mk_fun(io_poke_##SUF, e); \
}

DEF_POKE_INT(i8,  int8_t,   x < INT8_MIN || x > INT8_MAX)
DEF_POKE_INT(i16, int16_t,  x < INT16_MIN || x > INT16_MAX)
DEF_POKE_INT(i32, int32_t,  x < INT32_MIN || x > INT32_MAX)
DEF_POKE_INT(i64, int64_t,  0)
DEF_POKE_INT(u8,  uint8_t,  x < 0 || x > UINT8_MAX)
DEF_POKE_INT(u16, uint16_t, x < 0 || x > UINT16_MAX)
DEF_POKE_INT(u32, uint32_t, x < 0 || x > (long)UINT32_MAX)
DEF_POKE_INT(u64, uint64_t, x < 0)

static AhcNode *io_poke_d(AhcNode **env, AhcNode *w) {
  char *p = (char *)marshal_ptr(env[0], "poke");
  long off = ahc_eval(env[1])->u.i;
  double v = ahc_eval(env[2])->u.d;
  (void)w;
  memcpy(p + off, &v, sizeof v);
  return ahc_mk_con(UNIT_TAG, 0);
}

static AhcNode *p_poke_d(AhcNode *p, AhcNode *o, AhcNode *x) {
  AhcNode **e = ahc_env(3);
  e[0] = p; e[1] = o; e[2] = x;
  return ahc_mk_fun(io_poke_d, e);
}

static AhcNode *io_poke_p(AhcNode **env, AhcNode *w) {
  char *p = (char *)marshal_ptr(env[0], "poke");
  long off = ahc_eval(env[1])->u.i;
  void *v = ahc_eval(env[2])->u.p;
  (void)w;
  memcpy(p + off, &v, sizeof v);
  return ahc_mk_con(UNIT_TAG, 0);
}

static AhcNode *p_poke_p(AhcNode *p, AhcNode *o, AhcNode *x) {
  AhcNode **e = ahc_env(3);
  e[0] = p; e[1] = o; e[2] = x;
  return ahc_mk_fun(io_poke_p, e);
}

/* newCString: malloc'd NUL-terminated copy; release with free. */
static AhcNode *io_new_cstring(AhcNode **env, AhcNode *w) {
  (void)w;
  return ahc_mk_ptr(ahc_marshal_cstring(env[0]));
}

static AhcNode *p_new_cstring(AhcNode *s) {
  AhcNode **e = ahc_env(1);
  e[0] = s;
  return ahc_mk_fun(io_new_cstring, e);
}

/* peekCStringLen: exactly n bytes (NULs included). */
static AhcNode *io_peek_cstring_len(AhcNode **env, AhcNode *w) {
  char *p = (char *)marshal_ptr(env[0], "peekCStringLen");
  AhcNode *n = ahc_eval(env[1]);
  AhcNode *acc = ahc_mk_con(NIL_TAG, 0);
  long i;
  (void)w;
  if (n->tag != AHC_INT || n->u.i < 0)
    ahc_die("peekCStringLen: bad length");
  for (i = n->u.i; i > 0; i--) {
    AhcNode *ch = ahc_mk_char((unsigned char)p[i - 1]);
    AhcNode *c = ahc_mk_con(CONS_TAG, 2);   /* child first */
    c->u.con.fields[0] = ch;
    c->u.con.fields[1] = acc;
    acc = c;
  }
  return acc;
}

static AhcNode *p_peek_cstring_len(AhcNode *p, AhcNode *n) {
  AhcNode **e = ahc_env(2);
  e[0] = p; e[1] = n;
  return ahc_mk_fun(io_peek_cstring_len, e);
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
    char eb[512];
    fflush(stdout);
    snprintf(eb, sizeof eb, "%s: openFile: does not exist", pb.p);
    ahc_die(eb);
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
    char eb[512];
    fflush(stdout);
    snprintf(eb, sizeof eb, "%s: handle is closed", what);
    ahc_die(eb);
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
    char eb[512];
    fflush(stdout);
    snprintf(eb, sizeof eb, "%s: openFile: %s", pb.p,
             m == 0 ? "does not exist" : "cannot open");
    ahc_die(eb);
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
    AhcNode *sv = ahc_mk_string(ahc_argv[i]);   /* child first */
    AhcNode *cell = ahc_mk_con(CONS_TAG, 2);
    cell->u.con.fields[0] = sv;
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
    char eb[512];
    fflush(stdout);
    snprintf(eb, sizeof eb,
             "refinement violation: %g not in %g .. %g",
             v->u.d, l, h);
    ahc_die_raw(eb);
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
    char eb[512];
    fflush(stdout);
    if (v->tag == AHC_INT)
      snprintf(eb, sizeof eb,
               "refinement violation: predicate rejected %ld",
               v->u.i);
    else if (v->tag == AHC_CHAR)
      snprintf(eb, sizeof eb,
               "refinement violation: predicate rejected '%c'",
               (char)v->u.c);
    else
      snprintf(eb, sizeof eb,
               "refinement violation: predicate rejected the value");
    ahc_die_raw(eb);
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
    char eb[512];
    fflush(stdout);
    snprintf(eb, sizeof eb,
             "refinement violation: %ld not in %ld .. %ld",
             v->u.i, l, h);
    ahc_die_raw(eb);
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
  *ahc_prim_new_cstring, *ahc_prim_peek_cstring_len;

void ahc_rts_init(void) {
#ifdef AHC_USE_BOEHM
  GC_INIT();
  {
    struct GC_stack_base sb;
    GC_get_my_stackbottom(&sb);
    main_task.stack_top = (char *)sb.mem_base;
  }
#endif
#ifdef AHC_GC_OWN
  main_task.stack_top =
    (char *)pthread_get_stackaddr_np(pthread_self());
#endif
  stack_guard_pg = (size_t)sysconf(_SC_PAGESIZE);
  {
    /* Guard-page hits must be caught on their own stack (the
       faulting thread's has none left). */
    static char sigstk[SIGSTKSZ];
    stack_t ss;
    struct sigaction sa;
    ss.ss_sp = sigstk;
    ss.ss_size = sizeof sigstk;
    ss.ss_flags = 0;
    sigaltstack(&ss, NULL);
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = stack_overflow_handler;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
  }
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
  ahc_prim_scope = mk_prim1(p_scope);
  ahc_prim_spawn = mk_prim2(p_spawn);
  ahc_prim_await = mk_prim1(p_await);
  ahc_prim_chan_new = ahc_mk_fun(io_chan_new, NULL);
  ahc_prim_chan_send = mk_prim2(p_chan_send);
  ahc_prim_chan_recv = mk_prim1(p_chan_recv);
  ahc_prim_task_yield = ahc_mk_fun(io_task_yield, NULL);
  ahc_prim_wait_read = mk_prim1(p_wait_read);
  ahc_prim_wait_write = mk_prim1(p_wait_write);
  ahc_prim_try_recv = mk_prim1(p_try_recv);
  ahc_prim_select_recv = mk_prim1(p_select_recv);
  ahc_prim_wait_read_or = mk_prim2(p_wait_read_or);
  ahc_prim_prot_new = mk_prim1(p_prot_new);
  ahc_prim_prot_read = mk_prim2(p_prot_read);
  ahc_prim_prot_update = mk_prim2(p_prot_update);
  ahc_prim_prot_entry = mk_prim3(p_prot_entry);
  ahc_prim_par = mk_prim2(p_par);
  ahc_prim_pseq = mk_prim2(p_pseq);
  if (getenv("AHC_SPARK_STATS")) atexit(spark_stats);
  {                       /* watchdog budget: every build has one */
    const char *sl = getenv("AHC_SPIN_LIMIT");
    if (sl) ahc_spin_limit = atof(sl);
  }
#ifdef AHC_GC_OWN
  {
    const char *pv = getenv("AHC_OWN_PARANOID");
    own_paranoid_level = pv ? atoi(pv) : 0;
    own_madvise = getenv("AHC_OWN_MADVISE") != NULL;
    own_verify = getenv("AHC_OWN_VERIFY") != NULL;
    own_t_start = own_now();
  }
  if (getenv("AHC_OWN_STATS")) atexit(own_stats);
#endif
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
  ahc_prim_malloc_bytes = mk_prim1(p_malloc_bytes);
  ahc_prim_free_ptr = mk_prim1(p_free_ptr);
  ahc_prim_plus_ptr = mk_prim2(p_plus_ptr);
  ahc_prim_cast_ptr = mk_prim1(p_cast_ptr);
  ahc_prim_peek_i8 = mk_prim2(p_peek_i8);
  ahc_prim_peek_i16 = mk_prim2(p_peek_i16);
  ahc_prim_peek_i32 = mk_prim2(p_peek_i32);
  ahc_prim_peek_i64 = mk_prim2(p_peek_i64);
  ahc_prim_peek_u8 = mk_prim2(p_peek_u8);
  ahc_prim_peek_u16 = mk_prim2(p_peek_u16);
  ahc_prim_peek_u32 = mk_prim2(p_peek_u32);
  ahc_prim_peek_u64 = mk_prim2(p_peek_u64);
  ahc_prim_peek_d = mk_prim2(p_peek_d);
  ahc_prim_peek_p = mk_prim2(p_peek_p);
  ahc_prim_poke_i8 = mk_prim3(p_poke_i8);
  ahc_prim_poke_i16 = mk_prim3(p_poke_i16);
  ahc_prim_poke_i32 = mk_prim3(p_poke_i32);
  ahc_prim_poke_i64 = mk_prim3(p_poke_i64);
  ahc_prim_poke_u8 = mk_prim3(p_poke_u8);
  ahc_prim_poke_u16 = mk_prim3(p_poke_u16);
  ahc_prim_poke_u32 = mk_prim3(p_poke_u32);
  ahc_prim_poke_u64 = mk_prim3(p_poke_u64);
  ahc_prim_poke_d = mk_prim3(p_poke_d);
  ahc_prim_poke_p = mk_prim3(p_poke_p);
  ahc_prim_new_cstring = mk_prim1(p_new_cstring);
  ahc_prim_peek_cstring_len = mk_prim2(p_peek_cstring_len);
}
