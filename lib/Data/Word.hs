module Data.Word (Word, Word8, Word16, Word32, Word64) where

-- See Data.Int. `Word` is a SYNONYM for Word64 here (GHC's is a
-- distinct type of the same width) - the one observable divergence:
-- an instance written for Word64 also serves Word, and vice versa.
