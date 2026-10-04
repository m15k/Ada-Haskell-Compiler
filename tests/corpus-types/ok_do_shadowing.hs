-- Each do/comprehension/guard binding opens a new scope (Report 3.14):
-- rebinding a name in a later statement shadows. Only a name bound
-- twice by ONE pattern is an error (M142 review).
f :: Maybe Int -> Maybe Int -> Int
f a b
  | Just x <- a, Just x <- b = x
  | otherwise = 0

main :: IO ()
main = do
  x <- return (1 :: Int)
  x <- return (x + 1)
  let y = x
  let y' = y
  let y = y' + 1
  print [x | x <- [y], x <- [x, f Nothing Nothing]]
