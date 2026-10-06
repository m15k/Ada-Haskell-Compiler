module Foreign.C.Types
  ( CChar, CInt, CUInt, CLong, CULong, CSize
  ) where

-- Synonyms of the wired fixed-width types (LP64 widths), where GHC has
-- newtypes: AHC's CInt IS Int32, so arithmetic wraps at the type's
-- width as GHC's does, and the width is also enforced at the foreign
-- boundary.
