module Data.Functor.Identity (Identity (..)) where

-- The identity functor (M142), as base's: State s is StateT s Identity.

newtype Identity a = Identity { runIdentity :: a }

instance Functor Identity where
  fmap f (Identity a) = Identity (f a)

instance Applicative Identity where
  pure = Identity
  Identity f <*> Identity a = Identity (f a)

instance Monad Identity where
  return = Identity
  Identity a >>= k = k a

instance Show a => Show (Identity a) where
  showsPrec d (Identity a) =
    showParen (d >= 11) (showString "Identity " . showsPrec 11 a)

instance Eq a => Eq (Identity a) where
  Identity a == Identity b = a == b

instance Ord a => Ord (Identity a) where
  compare (Identity a) (Identity b) = compare a b
