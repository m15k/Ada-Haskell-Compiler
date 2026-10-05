import Control.Exception

big, small :: Int
big = maxBound
small = minBound

try' :: Int -> IO ()
try' x = do
  r <- try (evaluate x)
  putStrLn (either (\e -> "exception: " ++ show (e :: ArithException)) show r)

main :: IO ()
main = do
  print (big + 1, small - 1, big * 2, big * big, small * (-1))
  print (negate small, abs small, signum small, 2 ^ (64 :: Int) :: Int, 3 ^ (40 :: Int) :: Int)
  print (sum [big, big, big], product [1 .. 25 :: Int])
  print [ (x `quot` y, x `rem` y, x `div` y, x `mod` y)
        | x <- [big, small, 7, -7], y <- [3, -3, 1, -1], not (x == small && y == -1) ]
  print (small `rem` (-1), small `mod` (-1), quotRem 7 (-2 :: Int), divMod (-7) (2 :: Int))
  try' (small `div` (-1))
  try' (small `quot` (-1))
  try' (fst (quotRem small (-1)))
  try' (fst (divMod small (-1)))
  try' (1 `div` 0)
  try' (small `div` 0)
  try' (gcd small 6)
  try' (lcm big 2)
