module Main where
import qualified Left as L
import qualified Right as R

swapL :: L.Pair -> L.Pair
swapL (a, b) = (b, a)

flipR :: R.Pair -> R.Pair
flipR (a, b) = (not a, b)

main :: IO ()
main = do
  putStrLn (L.describe (swapL (2, 3)))
  putStrLn (R.describe (flipR (False, True)))
  putStrLn (L.name L.L ++ R.name R.R)
