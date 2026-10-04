-- The reader instances ((->) r) and Bounded at 2- to 7-tuples and
-- Ordering (with Ord/Enum Ordering), as base has them (M142 review:
-- possible once (->) became an ordinary type constructor in heads).
main :: IO ()
main = do
  print (fmap (+1) (*2) 3)
  print (((+) <*> (*2)) 5)
  print ((do { a <- (+1); b <- (*2); return (a + b) }) 3)
  print ((pure 7 :: Int -> Int) 99)
  print (((+1) >>= \a -> \r -> a * r) 4)
  print ((fmap show (+1) :: Int -> String) 41)
  print (((,) <$> fst <*> snd) (1 :: Int, 'x'))
  print (sequence [(+1), (*2), subtract 3] 10)
  print (minBound :: (Bool, Char, Int))
  print (maxBound :: (Bool, Ordering))
  print (minBound :: (Bool, Bool, Bool, Bool))
  print (maxBound :: (Bool, Bool, Bool, Bool, Bool))
  print (minBound :: (Bool, Bool, Bool, Bool, Bool, Bool))
  print (maxBound :: (Ordering, Bool, Bool, Bool, Bool, Bool, Char))
  print (minBound :: ())
  print (compare LT GT, [LT ..], succ LT, fromEnum GT, maximum [EQ, GT, LT], (minBound, maxBound) :: (Ordering, Ordering))
