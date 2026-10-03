module Main where
import Left
import Right
main :: IO ()
main = print (Left.area (Circle 2.0))
