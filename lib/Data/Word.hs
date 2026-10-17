module Data.Word (Word, Word8, Word16, Word32, Word64) where

-- See Data.Int. `Word` is its own type of Word64's width, as GHC's
-- (M150): an instance for Word64 does not serve Word.
