-- Bounded at Int and Char (M142, found by Printf's %u): minBound and
-- maxBound had no runtime ("method 'minBound' has no runtime yet").
main :: IO ()
main = do
  print (minBound :: Int, maxBound :: Int)
  print (minBound :: Char, maxBound :: Char)
  print ([minBound .. maxBound :: Bool], succ (minBound :: Int))
  print (fromEnum (maxBound :: Char), (maxBound :: Int) `div` 2)
