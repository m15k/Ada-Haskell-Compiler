import Data.List (foldl')

main :: IO ()
main = print (foldl' (+) 0 [1 .. 2000000 :: Integer])
