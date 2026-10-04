module Foreign.C.String
  ( CString, newCString, peekCString, peekCStringLen
  ) where

-- AHC's C-string primitives work on `Ptr Char` (a NUL-terminated UTF-8
-- buffer), so CString is that, not GHC's `Ptr CChar`. GHC's withCString,
-- castCharToCChar and friends are absent.
type CString = Ptr Char
