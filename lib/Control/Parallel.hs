module Control.Parallel (par, pseq) where

-- Sparks: deterministic parallelism for pure code
-- (docs/concurrency-design-note.md section 7, stage B1).
--
--   a `par` b   hints that a may be evaluated in parallel, then
--               returns b. The hint is ADVISORY: a spark may be
--               evaluated by a worker OS thread, by whoever
--               demands it, or never - purity makes all three the
--               same answer. par changes wall time, never results.
--   a `pseq` b  evaluates a to WHNF, then returns b - seq with a
--               guaranteed order, for staging demand around par.
--
-- Worker threads evaluate pure thunks only; IO stays on the main
-- thread under the deterministic scheduler, so every golden a
-- program had without workers it keeps with them. An error inside
-- sparked code surfaces exactly when the program demands the
-- value, not when a worker happens to hit it.
--
-- The pool starts on the first par (AHC_WORKERS to size it, 0 to
-- disable; AHC_SPARK_STATS=1 prints created/converted/fizzled/
-- dropped at exit - watch the fizzle rate, not just the clock).

infixr 0 `par`, `pseq`

par :: a -> b -> b
par = primPar

pseq :: a -> b -> b
pseq = primPseq
