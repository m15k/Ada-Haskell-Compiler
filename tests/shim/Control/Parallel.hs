-- GHC implementation of AHC's Control.Parallel for differential
-- testing (runghc -i tests/shim). GHC's own par/pseq live in
-- GHC.Conc (base) - the sparks AHC's B1 borrows are GHC's design,
-- so the shim is a re-export. Note runghc evaluates on one
-- capability unless told otherwise; that is fine, because par
-- programs' OUTPUT is capability-count-independent by design.
module Control.Parallel (par, pseq) where

import GHC.Conc (par, pseq)
