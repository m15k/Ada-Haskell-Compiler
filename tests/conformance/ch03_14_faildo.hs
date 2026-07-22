-- Report 3.14: refutable patterns in do-binds desugar to the
-- monad's fail. Maybe -> Nothing, [] -> [] (skip); the nested
-- cons pattern pins the join-point fix (fail must be let-bound,
-- or nested failure positions share one node).
firstJust :: [(String, Int)] -> Maybe Int
firstJust ps = do
  Just v <- Just (lookup "k" ps)
  return v

pairsOf :: [[Int]] -> [(Int, Int)]
pairsOf xss = do
  (x : y : _) <- xss
  return (x, y)

main :: IO ()
main = do
  print (firstJust [("k", 42)], firstJust [("z", 1)])
  print (pairsOf [[1, 2, 3], [9], [4, 5]])
