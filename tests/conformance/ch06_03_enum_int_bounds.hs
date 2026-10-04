-- Int enumerations stop at maxBound/minBound instead of wrapping, and
-- succ/pred at the bounds raise GHC's error texts, as do Char's past
-- its range (M142 review).
import Control.Exception
main :: IO ()
main = do
  print (take 5 [maxBound - 2 :: Int ..])
  print (take 5 [minBound + 2 :: Int, minBound + 1 ..])
  print (take 5 [maxBound - 5 :: Int, maxBound - 3 ..])
  print (take 5 [maxBound - 5 :: Int, maxBound - 2 ..])
  print [maxBound - 2 :: Int .. maxBound]
  print [minBound :: Int .. minBound + 2]
  print [maxBound - 4 :: Int, maxBound - 2 .. maxBound]
  print [minBound + 4 :: Int, minBound + 2 .. minBound]
  print [minBound :: Int, maxBound .. maxBound]
  print (length [maxBound - 10 :: Int, maxBound - 7 ..])
  print (succ (maxBound - 1 :: Int), pred (minBound + 1 :: Int))
  print (take 3 [maxBound :: Char ..], succ 'a', pred 'b')
  r1 <- try (evaluate (succ (maxBound :: Int)))
  case r1 of
    Left e -> putStrLn ("succ: " ++ show (e :: ErrorCall))
    Right v -> print v
  r2 <- try (evaluate (pred (minBound :: Int)))
  case r2 of
    Left e -> putStrLn ("pred: " ++ show (e :: ErrorCall))
    Right v -> print v
  r3 <- try (evaluate (succ (maxBound :: Char)))
  case r3 of
    Left e -> putStrLn ("succC: " ++ show (e :: ErrorCall))
    Right v -> print v
  r4 <- try (evaluate (pred (minBound :: Char)))
  case r4 of
    Left e -> putStrLn ("predC: " ++ show (e :: ErrorCall))
    Right v -> print v
