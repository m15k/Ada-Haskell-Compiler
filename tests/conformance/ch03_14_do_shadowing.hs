-- Each binding statement opens a new scope over the statements after
-- it (Report 3.14): rebinding a name in a later do, comprehension or
-- pattern-guard statement shadows (M142 review: AHC said "'x' is
-- bound more than once"). One pattern binding a name twice is still an
-- error (tests/corpus-types/bad_do_pattern_duplicate.hs).
f :: Maybe Int -> Maybe Int -> Int
f a b
  | Just x <- a, Just x <- b = x
  | otherwise = 0

main :: IO ()
main = do
  x <- return (1 :: Int)
  print x
  x <- return (x + 10)
  print x
  let y = x * 2
  let y' = y
  let y = y' + 1
  print y
  (x, z) <- return (x, x + 1)
  print (x, z)
  print [x | x <- [1, 2, 3 :: Int], x <- [x, x * 10]]
  print (f (Just 1) (Just 2), f Nothing (Just 3))
  r <- return (do { a <- Just 'a'; a <- Just [a, a]; return a })
  print r
