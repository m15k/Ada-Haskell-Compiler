-- a local letrec function pushes its own name; a counted loop folds
total :: [Int] -> Int
total = go 0
  where
    go acc [] = acc `div` 0
    go acc (x:xs) = go (acc + x) xs

main :: IO ()
main = print (total [1 .. 5])
