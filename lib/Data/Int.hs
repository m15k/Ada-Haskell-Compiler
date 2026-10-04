module Data.Int (Int, Int8, Int16, Int32, Int64) where

-- The fixed-width types are wired in (they carry the FFI's exact C
-- widths, chapter 10), so their NAMES live in the compiler, but the
-- Prelude does not export them (as in GHC): this module is where a
-- program imports them from. Their arithmetic wraps like GHC's: every result
-- is Int's result narrowed to the width (prelude/Prelude.hs, the
-- generated fixed-width block; docs/plans/2026-09-08-m139-int-word-ioref.md).
