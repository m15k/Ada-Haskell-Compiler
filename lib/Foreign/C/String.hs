module Foreign.C.String
  ( CString, CStringLen, newCString, peekCString, peekCStringLen
  ) where

-- AHC's C-string primitives work on `Ptr Char` (a NUL-terminated UTF-8
-- buffer), so CString is that, not GHC's `Ptr CChar`. GHC's withCString,
-- castCharToCChar and friends are absent.
type CString = Ptr Char

type CStringLen = (CString, Int)

-- GHC's shape: the pointer and length travel as a pair. (The wired
-- primitive is curried; AHC.FFI exports that one as peekCStringLen.)
peekCStringLen :: CStringLen -> IO String
peekCStringLen (p, n) = Prelude.peekCStringLen p n
