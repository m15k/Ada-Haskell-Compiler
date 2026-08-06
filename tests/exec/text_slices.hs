-- AHC-pinned Text behavior: byteLength (O(1), AHC-only), slicing at
-- multibyte boundaries, and slice-of-slice sharing.
import qualified Data.Text as T

main :: IO ()
main = do
  let t = T.pack "a\955\28450\128077z"     -- 1+2+3+4+1 bytes
  print (T.length t, T.byteLength t)
  let m = T.drop 1 (T.take 4 t)            -- slice of a slice
  print (T.unpack m, T.length m, T.byteLength m)
  print (map (T.byteLength . flip T.take t) [0 .. 5])
  print (T.unpack (T.drop 3 t))
  print (T.take 3 (T.drop 1 t) == T.pack "\955\28450\128077")
  print (T.drop 99 t == T.pack "", T.take 99 t == t)
