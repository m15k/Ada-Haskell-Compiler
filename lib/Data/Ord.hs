module Data.Ord (comparing, Down (..)) where

comparing :: Ord a => (b -> a) -> b -> b -> Ordering
comparing f x y = compare (f x) (f y)

newtype Down a = Down a deriving (Eq, Show)

instance Ord a => Ord (Down a) where
  compare (Down x) (Down y) = compare y x
  (<) a b = compare a b == LT
  (<=) a b = compare a b /= GT
  (>) a b = compare a b == GT
  (>=) a b = compare a b /= LT
  max a b = if compare a b == LT then b else a
  min a b = if compare a b == GT then b else a
