module Data.Ord (comparing, Down (..)) where

comparing :: Ord a => (b -> a) -> b -> b -> Ordering
comparing f x y = compare (f x) (f y)

newtype Down a = Down a deriving (Eq, Show)

instance Ord a => Ord (Down a) where
  compare (Down x) (Down y) = compare y x
