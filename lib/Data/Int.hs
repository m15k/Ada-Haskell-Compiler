module Data.Int (Int, Int8, Int16, Int32, Int64) where

-- The fixed-width types are wired in (they carry the FFI's exact C
-- widths, chapter 10), so like `Int` their NAMES need no import in
-- AHC; this module exists for GHC-portable programs that write
-- `import Data.Int`. Their arithmetic wraps like GHC's: every result
-- is Int's result narrowed to the width (prelude/Prelude.hs, the
-- generated fixed-width block; docs/plans/2026-09-08-m139-int-word-ioref.md).
