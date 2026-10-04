-- Superclass dictionaries of instances WITH contexts (M142 review).
-- Building `Ord (T a)`'s Eq superclass means solving `Eq (T a)`, whose
-- instance context `Eq a` must be instantiated at the head and then
-- found by superclass entailment from the given `Ord a`; AHC's
-- elaborator did neither and the program died "$dMISSING".
import Data.Ratio

data T a = T a

instance Eq a => Eq (T a) where
  T a == T b = a == b

instance Ord a => Ord (T a) where
  compare (T a) (T b) = compare a b

-- the context differs from the superclass's own
data U a = U a

instance Show a => Eq (U a) where
  U a == U b = show a == show b

instance Show a => Ord (U a) where
  compare (U a) (U b) = compare (show a) (show b)

-- two levels: Pair's Ord needs Eq (Pair a b) which needs Eq a, Eq b
data Pair a b = Pair a b

instance (Eq a, Eq b) => Eq (Pair a b) where
  Pair a b == Pair c d = a == c && b == d

instance (Ord a, Ord b) => Ord (Pair a b) where
  compare (Pair a b) (Pair c d) = compare (a, b) (c, d)

newtype W a = W a

instance Eq a => Eq (W a) where
  W a == W b = a == b

instance Ord a => Ord (W a) where
  W a <= W b = a <= b

f :: Ord a => a -> a -> Bool
f x y = x == y

g :: Fractional a => a -> a
g x = x / 2

h :: Integral a => a -> a -> Bool
h x y = x == y && x <= y

main :: IO ()
main = do
  print (f (T 'a') (T 'a'), f (T 'a') (T 'b'))
  print (f (U 'a') (U 'a'), f (U (1 :: Int)) (U 2))
  print (f (Pair 'a' True) (Pair 'a' True), f (Pair (T 'x') 1) (Pair (T 'x') (2 :: Int)))
  print (f (W (T (U 'q'))) (W (T (U 'q'))))
  print (g (3 % 1 :: Rational), g (toRational (3 :: Int)))
  print (g (1 % 3 :: Ratio Int))
  print (h (4 :: Int) 4, h (5 :: Integer) 4)
  print (compare (T (Pair 1 'b')) (T (Pair (1 :: Int) 'a')), max (W 'a') (W 'z') <= W 'z')
  -- the Prelude's own `instance Semigroup a => Monoid (Maybe a)` had
  -- the same $dMISSING superclass (its Core golden showed it)
  print (mconcat [Just [1 :: Int], Nothing, Just [2]], mappend (Just "x") mempty)
