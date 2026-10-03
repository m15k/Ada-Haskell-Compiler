module Main where
import qualified Left as L
import qualified Right as R

classify :: R.Shape -> String
classify (R.Circle _) = "round"
classify (R.Square _) = "square"

main :: IO ()
main = do
  print (L.area (L.Circle 2.0))
  print (R.area (R.Square 3))
  print (map L.area [L.Circle 1.0, L.Square 2.0])
  print (R.Circle 4, R.Circle 4 == R.Square 4)
  putStrLn (classify (R.Circle 1))
