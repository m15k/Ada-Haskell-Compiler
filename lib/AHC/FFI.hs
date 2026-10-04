module AHC.FFI
  ( peekInt8, peekInt16, peekInt32, peekInt64
  , peekWord8, peekWord16, peekWord32, peekWord64
  , peekDouble, peekPtr
  , pokeInt8, pokeInt16, pokeInt32, pokeInt64
  , pokeWord8, pokeWord16, pokeWord32, pokeWord64
  , pokeDouble, pokePtr
  ) where

-- AHC-ONLY (no GHC home): raw memory access at a BYTE OFFSET from a
-- Ptr, memcpy'd so alignment never bites, poke values range-checked
-- (MANUAL chapter 10). GHC's Storable (peek/poke/peekByteOff/sizeOf)
-- has a different, class-based shape; this module is not portable to GHC.
