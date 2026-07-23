-- Function contracts (docs/contracts-design-note.md): demand-time
-- claims; the violation message and exit are part of the golden.
{-# PRE  clamp \lo hi x -> lo <= hi #-}
{-# POST clamp \lo hi x r -> lo <= r && r <= hi #-}
clamp :: Int -> Int -> Int -> Int
clamp lo hi x = max lo (min hi x)

{-# POST doubled \x r -> r == x + x #-}
doubled :: Int -> Int
doubled x = x * 3

{-# PRE  headOf \xs -> not (null xs) #-}
headOf :: [Int] -> Int
headOf (x : _) = x

{-# PRE  gsum \xs n -> n >= 0 #-}
{-# POST gsum \xs n r -> r >= n #-}
gsum :: Num a => [a] -> Int -> Int
gsum _ n = n + 1

main :: IO ()
main = do
  print (clamp 0 10 42, clamp 0 10 (-5))
  print (gsum [1.5 :: Double, 2.5] 4)
  let unused = headOf []           -- never demanded: no check
  print (headOf [7, 8])
  print (doubled 5)                -- postcondition violation dies
