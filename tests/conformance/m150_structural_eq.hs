-- M150 D1: wired and derived Eq/Ord call a component's own instance
-- whenever that instance is not structural.
import Data.Char (toLower)

newtype Ci = Ci String deriving Show

instance Eq Ci where
  Ci a == Ci b = map toLower a == map toLower b

instance Ord Ci where
  compare (Ci a) (Ci b) = compare (map toLower a) (map toLower b)

data P = P Ci Int deriving (Eq, Ord, Show)

data Rec = Rec { name :: Ci, tags :: [Ci] } deriving (Eq, Ord, Show)

data Tree a = Leaf | Node (Tree a) a (Tree a) deriving (Eq, Ord, Show)

data Shape = Dot | Box Int Int | Named Ci deriving (Eq, Ord, Show)

-- Polymorphic code: the element dictionary arrives at run time.
same :: Eq a => [a] -> [a] -> Bool
same xs ys = xs == ys

order :: Ord a => a -> a -> Ordering
order = compare

-- Ord's Eq superclass, reached from an Ord context alone.
viaOrd :: Ord a => a -> a -> Bool
viaOrd x y = x == y

main :: IO ()
main = do
  print ([Ci "A"] == [Ci "a"], [Ci "A"] /= [Ci "a"])
  print (Just (Ci "X") == Just (Ci "x"), (Ci "a", 1 :: Int) == (Ci "A", 1))
  print (Left (Ci "q") == (Left (Ci "Q") :: Either Ci Int))
  print (P (Ci "Hi") 3 == P (Ci "hI") 3, P (Ci "Hi") 3 == P (Ci "hI") 4)
  print (Rec (Ci "N") [Ci "t"] == Rec (Ci "n") [Ci "T"])
  print (Node Leaf (Ci "K") Leaf == Node Leaf (Ci "k") Leaf)
  print (compare [Ci "b"] [Ci "A"], compare (Just (Ci "a")) (Just (Ci "A")))
  print (compare (P (Ci "a") 2) (P (Ci "A") 1), P (Ci "a") 1 < P (Ci "B") 0)
  print (compare Dot (Box 1 2), compare (Box 1 2) (Named (Ci "z")))
  print (compare (Named (Ci "Z")) (Named (Ci "z")), Box 2 1 > Box 1 9)
  print (maximum [Ci "b", Ci "C", Ci "a"], minimum [P (Ci "b") 1, P (Ci "B") 0])
  print (same [Ci "M"] [Ci "m"], same [1, 2 :: Int] [1, 2])
  print (order (Node Leaf (Ci "a") Leaf) (Node Leaf (Ci "A") Leaf))
  print (viaOrd [1, 2 :: Int] [1, 2], viaOrd (Just (Ci "u")) (Just (Ci "U")))
  print (viaOrd (Node Leaf [Ci "x"] Leaf) (Node Leaf [Ci "X"] Leaf))
  print ("abc" == "abc", [[1, 2], [3 :: Int]] < [[1, 2], [4]], compare "b" "ab")
  print (Node Leaf (1 :: Int) Leaf == Node Leaf 1 Leaf, [Dot, Box 1 1] < [Dot, Box 1 2])
  -- Report 6.3.2's max/min: a tie answers max = y, min = x.
  print (max (P (Ci "A") 1) (P (Ci "a") 1), min (P (Ci "A") 1) (P (Ci "a") 1))
  print (max [Ci "x"] [Ci "X"], max 0.0 (-0.0 :: Double), min (-0.0) (0.0 :: Double))
