-- Every contract here is provably true at compile time: the
-- discharge evaluator must drop ALL claims (the harness greps the
-- generated C for check_claim and expects none).
{-# PRE  scale \x -> True #-}
{-# POST scale \x r -> 2 + 2 == 4 #-}
scale :: Int -> Int
scale x = x * 10

{-# PRE bump \x -> 10 > 3 #-}
{-# POST bump \x r -> even 4 #-}
bump :: Int -> Int
bump x = x + 1

{-# PRE mix \a b -> (3 * 3 == 9) && (17 `mod` 5 == 2) #-}
mix :: Int -> Int -> Int
mix a b = a + b

main :: IO ()
main = do
  print (scale 4)
  print (bump 41)
  print (mix 1 2)
