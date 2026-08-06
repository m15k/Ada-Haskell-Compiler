-- M_Text through the FFI: Text crosses as const char* (UTF-8,
-- copied both ways, normalized inbound), alongside hPutText /
-- hGetContentsText at System.IO handles.
{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE OverloadedStrings #-}
import qualified Data.Text as T
import System.IO

foreign import ccall "setenv"
  cSetenv :: T.Text -> T.Text -> Int -> IO Int
foreign import ccall "getenv" cGetenv :: T.Text -> IO T.Text
foreign import ccall "strlen" cStrlen :: T.Text -> Int

main :: IO ()
main = do
  _ <- cSetenv "AHC_FFI_TEXT" "v\229lue \955\28450" 1
  v <- cGetenv "AHC_FFI_TEXT"
  print (v, T.length v, T.byteLength v)
  print (cStrlen "\955\28450")            -- C sees UTF-8 bytes
  hPutText stdout "via hPutText: \955\n"
  h <- openFile "ffi_text.tmp" WriteMode
  hPutText h "f\239le \955"
  hClose h
  h2 <- openFile "ffi_text.tmp" ReadMode
  t <- hGetContentsText h2
  hClose h2
  print (t == "f\239le \955", T.length t, T.byteLength t)
