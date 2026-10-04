module Foreign
  ( module Data.Int, module Data.Word
  , module Foreign.Ptr, module Foreign.Marshal
  ) where

-- GHC's Foreign also re-exports Data.Bits, Foreign.ForeignPtr,
-- Foreign.StablePtr and Foreign.Storable; AHC has no ForeignPtr,
-- StablePtr or Storable class (see AHC.FFI for the raw peek/poke family).
import Data.Int
import Data.Word
import Foreign.Ptr
import Foreign.Marshal
