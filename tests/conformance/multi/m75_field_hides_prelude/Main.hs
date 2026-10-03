module Main where
import Prelude hiding (length)
data P = P { length :: Int } deriving Show
main :: IO ()
main = print (length (P 3), (P 1) { length = 9 })
