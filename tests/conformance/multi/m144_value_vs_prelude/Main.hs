module Main where
filter :: Int -> Int
filter x = x + 1
main :: IO ()
main = print (filter 3)
