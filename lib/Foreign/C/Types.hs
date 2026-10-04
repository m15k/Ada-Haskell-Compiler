module Foreign.C.Types
  ( CChar, CInt, CUInt, CLong, CULong, CSize
  ) where

-- Synonyms of the wired fixed-width types (LP64 widths), where GHC has
-- newtypes: AHC's CInt IS Int32, arithmetic promotes rather than wraps,
-- and the width is enforced at the foreign boundary only.
