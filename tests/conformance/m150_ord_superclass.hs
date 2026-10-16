-- M150 D1: an Ord dictionary for a type with a context carries its
-- Eq superclass applied to the element's Eq (it was the unapplied
-- instance function: "selector on a non-dictionary").
data T a = A | B a deriving (Eq, Ord, Show)

eqViaOrd :: Ord a => a -> a -> Bool
eqViaOrd x y = x == y

neViaOrd :: Ord a => a -> a -> Bool
neViaOrd x y = x /= y

main :: IO ()
main = do
  print (eqViaOrd [1, 2] [1, 2 :: Int], neViaOrd "ab" "ac")
  print (eqViaOrd (Just 'a') (Just 'a'), eqViaOrd (1 :: Int, 'x') (1, 'y'))
  print (eqViaOrd (B [1 :: Int]) (B [1]), eqViaOrd A (B 'c'))
  print (eqViaOrd (Left 3 :: Either Int Bool) (Left 3))
