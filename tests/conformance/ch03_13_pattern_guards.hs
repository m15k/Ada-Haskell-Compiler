-- Report 3.13: guards are qualifier sequences - boolean tests,
-- pattern guards, and lets.
lookupDefault :: Int -> [(Int, String)] -> String
lookupDefault k m
  | Just v <- lookup k m = v
  | otherwise            = "missing"

classify :: [Int] -> String
classify xs
  | (y : _) <- xs, even y, let z = y * 10, z > 50 = "big even head"
  | (y : _) <- xs, even y = "small even head"
  | null xs = "empty"
  | otherwise = "odd head"

main :: IO ()
main = do
  putStrLn (lookupDefault 2 [(1, "a"), (2, "b")])
  putStrLn (lookupDefault 9 [(1, "a")])
  mapM_ (putStrLn . classify) [[6, 1], [2, 1], [3], []]
  print (case [1, 2] of { ys | (a : b : _) <- ys, a < b -> a + b; _ -> 0 })
