-- A PRE contract sees through a synonym for a partially applied (->)
-- (M142 review: `inc3 :: Q Int` with `type Q = (->) Int` was "a value
-- binding" whose PRE was rejected - the synonym's surplus argument
-- built a raw (->) spine instead of an arrow).
{-# PRE inc2 \x -> x > 0 #-}
inc2 :: (->) Int Int
inc2 x = x + 1

type Q = (->) Int
{-# PRE inc3 \x -> x > 0 #-}
inc3 :: Q Int
inc3 x = x + 1

main :: IO ()
main = do
  print (inc2 41)
  print (inc3 41)
  print (inc3 (-3))
