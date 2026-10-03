module Control.Monad.State.Strict (module Control.Monad.State) where

-- mtl's Strict variant differs only in the strictness of the state
-- pair; AHC ships the one StateT (the difference shows only with
-- bottoms in the pair - documented in EXCLUSIONS).

import Control.Monad.State
