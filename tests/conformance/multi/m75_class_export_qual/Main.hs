module Main where
import Mid
data W = W
instance Named W where name _ = "W"
main :: IO ()
main = putStrLn (name (3 :: Int) ++ name W)
