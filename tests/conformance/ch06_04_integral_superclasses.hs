-- Report 6.4: class (Real a, Enum a) => Integral a. An Integral
-- constraint alone must give Real (realToFrac, toRational, Ord) and
-- Enum ([a .. b], succ, fromEnum).
upTo :: Integral a => a -> [a]
upTo n = [1 .. n]

mean :: Integral a => [a] -> Double
mean xs = realToFrac (sum xs) / fromIntegral (length xs)

nextOdd :: Integral a => a -> a
nextOdd n = if odd n then succ (succ n) else succ n

biggest :: Integral a => [a] -> a
biggest = foldr1 max

main :: IO ()
main = do
  print (upTo (5 :: Int), upTo (3 :: Integer))
  print (mean [1, 2, 3, 4 :: Int], mean [10, 20 :: Integer])
  print (nextOdd (7 :: Int), nextOdd (10 :: Integer), fromEnum (nextOdd (3 :: Int)))
  print (biggest [3, 9, 2 :: Int])
