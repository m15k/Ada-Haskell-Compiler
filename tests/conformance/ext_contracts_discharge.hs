-- Contracts provably true at compile time are DISCHARGED - the
-- claims vanish from the generated code (scripts/run_discharge.sh
-- proves the vanishing; this program proves the observable
-- behavior is untouched). GHC ignores the pragmas entirely, so
-- byte-identical output here pins both properties at once.
{-# PRE  scale \x -> True #-}
{-# POST scale \x r -> 2 + 2 == 4 #-}
scale :: Int -> Int
scale x = x * 10

{-# PRE mix \a b -> (3 * 3 == 9) && (17 `mod` 5 == 2) && even 4 && (10 > 3) #-}
mix :: Int -> Int -> Int
mix a b = a + b

main :: IO ()
main = do
  print (scale 4)
  print (mix 1 2)
