module AHC.Prim
  ( primCatch, primEvaluate, primThrowIO, primThrow
  , primExcKind, primExcCode, primExcMessage, primExcIO
  , primExcErrorCall, primExcExit, primExcFromIO, primExcArith
  , primIoeType, primIoeLocation, primIoeFilename, primIoeDescription
  , primMkIOError
  ) where

-- INTERNAL and UNSTABLE: the exception and IOError primitives the
-- compiler's own tests drive directly. Not a GHC module; user programs
-- should use Control.Exception and System.IO.Error. The Prelude does not
-- export these (it exports what GHC's does); library modules see them
-- through the whole Prelude, and this module re-exports them.
