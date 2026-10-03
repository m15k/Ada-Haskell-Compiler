module Main where
import qualified V
f :: Int -> String
f 0 = "zero"
f _ = "other"
main :: IO ()
main = print (f 5, (V.==) 1 2)
