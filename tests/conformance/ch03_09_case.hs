-- Report 3.13: case expressions with guards and nested patterns.
describe :: [Int] -> Int
describe xs = case xs of
  []        -> 0
  [x] | x > 0     -> x
      | otherwise -> negate x
  (x : y : _) -> x + y

main :: IO ()
main = do
  print (describe [])
  print (describe [7])
  print (describe [-7])
  print (describe [1, 2, 3])
  print (case Just 5 of { Nothing -> 0; Just n -> n * 2 })
