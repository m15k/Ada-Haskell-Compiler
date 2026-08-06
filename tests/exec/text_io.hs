-- Text IO pins: file round trip at the byte level, putText's raw
-- fwrite, and the C-string bridges (AHC-only surface).
import qualified Data.Text as T
main :: IO ()
main = do
  let t = T.pack "h\233llo \955\28450 \128077"
  T.writeFileText "text_io.tmp" t
  r <- T.readFileText "text_io.tmp"
  print (r == t, T.length r, T.byteLength r)
  T.putTextLn (T.append (T.pack ">> ") r)
  p <- T.textNewCString (T.pack "caf\233")
  b <- T.textFromCStringLen p 5
  print (b == T.pack "caf\233", T.byteLength b)
  free p
