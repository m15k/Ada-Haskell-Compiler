-- custom Eq superclass under GND Ord
newtype Age = Age Int deriving (Show, Ord)
instance Eq Age where _ == _ = True
viaOrd :: Ord a => a -> a -> Bool
viaOrd x y = x == y
main :: IO ()
main = do
  print (Age 1 == Age 2)
  print (viaOrd (Age 1) (Age 2))
  print (compare (Age 1) (Age 2))
