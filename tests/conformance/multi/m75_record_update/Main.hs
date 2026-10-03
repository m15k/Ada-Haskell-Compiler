module Main where
import qualified L
import qualified R
main :: IO ()
main = do
  print ((R.Shape 1) { R.radius = 4 })
  print ((L.Shape 1 "x") { L.radius = 5 })
  case R.Shape 2 of R.Shape { R.radius = r } -> print r
  print (R.Shape { R.radius = 3 })
