module Main where
import qualified Left as L
import qualified Right as R
f :: L.Shape -> Int
f _ = 1
main :: IO ()
main = print (f (R.Circle 1))
