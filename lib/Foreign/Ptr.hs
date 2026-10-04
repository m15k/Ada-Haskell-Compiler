module Foreign.Ptr
  ( Ptr, FunPtr, nullPtr, castPtr, plusPtr, nullFunPtr
  , freeHaskellFunPtr
  ) where

-- The pointer types and operations are wired into the compiler (the FFI
-- marshals them, chapter 10); this module is their GHC home. Absent from
-- GHC's Foreign.Ptr: minusPtr, alignPtr, castFunPtr, IntPtr/WordPtr.
