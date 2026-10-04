module Main where
import L
data Blob = Circle Bool deriving Show
main :: IO ()
main = print (Circle True)
