-- Report 6.3.4: Enum at Char (over ord/chr) and Double (numeric
-- enumeration, k-indexed stepping and the half-step limit rule).
main :: IO ()
main = do
  print ['a' .. 'f']
  print ['a', 'c' .. 'i']
  print (succ 'a', pred 'z')
  print (fromEnum 'A', (toEnum 66 :: Char))
  print (take 4 ['x' ..])
  print [1.0 .. 5.0 :: Double]
  print [1.0, 1.5 .. 3.0 :: Double]
  print [0.1, 0.2 .. 0.5 :: Double]
  print [5.0, 4.0 .. 1.0 :: Double]
  print (succ (1.5 :: Double), pred (1.5 :: Double))
  print (take 3 [2.5 :: Double ..])
  print (fromEnum (3.9 :: Double), (toEnum 7 :: Double))
