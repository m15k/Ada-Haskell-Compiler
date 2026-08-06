-- Data.Text common subset, GHC-oracled (GHC's boot text package).
-- Restricted to functions both compilers export with identical
-- semantics; byteLength is AHC-only and pinned in tests/exec.
import qualified Data.Text as T

main :: IO ()
main = do
  let t = T.pack "h\233llo \955\28450"
  print (T.length t)
  print (T.unpack t == "h\233llo \955\28450")
  print (T.null t, T.null (T.pack ""))
  print (T.append (T.pack "ab") (T.pack "\955c"))
  print (T.concat [T.pack "x", T.pack "\228", T.pack "z"])
  print (T.intercalate (T.pack ", ") [T.pack "a", T.pack "b"])
  print (T.index t 1, T.index t 6)
  print (T.take 2 t, T.drop 6 t)
  print (T.splitAt 6 t)
  print (T.singleton '\955')
  print (t == T.pack "h\233llo \955\28450", t == T.pack "x")
  print (compare (T.pack "ab") (T.pack "b"),
         compare (T.pack "\955") (T.pack "z"))
  print (show t)
