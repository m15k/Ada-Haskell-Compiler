module Main where
import qualified Left as L
import qualified Right as R
main :: IO ()
main = do
  print (L.A 1, R.A 2, L.mk 3, R.mk 4)
  putStrLn (L.c (L.A 1) ++ R.c (R.B 5))
  putStrLn (L.c L.Y ++ R.c R.Z)
  print (L.upd (L.B 1), R.upd (R.B 2))
  print (compare (L.A 1) (L.B 2), R.A 3 == R.A 3, [minBound .. maxBound :: R.E])
  print (L.N 3, R.N 4)
