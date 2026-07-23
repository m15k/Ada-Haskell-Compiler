-- Function contracts as pragmas: GHC ignores them (an
-- Unrecognised-pragma warning on stderr), so a program whose
-- contracts HOLD is byte-identical under both compilers - the
-- oracle-portability property from the design note.
{-# PRE  clamp \lo hi x -> lo <= hi #-}
{-# POST clamp \lo hi x r -> lo <= r && r <= hi #-}
clamp :: Int -> Int -> Int -> Int
clamp lo hi x = max lo (min hi x)

{-# PRE  isqrt \n -> n >= 0 #-}
{-# POST isqrt \n r -> r * r <= n && n < (r + 1) * (r + 1) #-}
isqrt :: Integer -> Integer
isqrt n = go 0
  where
    go k = if (k + 1) * (k + 1) > n then k else go (k + 1)

{-# POST merged \xs ys r -> length r == length xs + length ys #-}
merged :: [Int] -> [Int] -> [Int]
merged [] ys = ys
merged xs [] = xs
merged (x : xs) (y : ys) =
  if x <= y then x : merged xs (y : ys) else y : merged (x : xs) ys

main :: IO ()
main = do
  print (clamp 0 100 250, clamp 0 100 (-3), clamp 0 100 42)
  print (map isqrt [0, 1, 2, 15, 16, 17, 10 ^ 12])
  print (merged [1, 4, 9] [2, 3, 10])
