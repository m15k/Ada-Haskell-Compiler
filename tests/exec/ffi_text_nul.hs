-- A NUL-terminated wire format cannot carry an interior NUL, and
-- each host would hide that differently (Rust errors, C/C++/Go/GHC
-- truncate). AHC refuses it once, at the marshal, so every spoke
-- sees the same clean failure instead of silently losing data.
-- (The success path lives in ffi_text.hs.)
{-# LANGUAGE ForeignFunctionInterface #-}
import qualified Data.Text as T

foreign import ccall "strlen" cStrlen :: T.Text -> Int

main :: IO ()
main = print (cStrlen (T.pack "a\0b"))
