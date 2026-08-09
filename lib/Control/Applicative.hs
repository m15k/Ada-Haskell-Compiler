module Control.Applicative
  ( Applicative (..)
  , Alternative (..)
  , Const (..)
  , WrappedMonad (..)
  , ZipList (..)
  , (<$>), (<$), (<**>)
  , liftA, liftA2, liftA3
  , optional
  , asum
  ) where

--  GHC 9.4.8's Control.Applicative, minus what AHC cannot yet
--  express: WrappedArrow (no Arrow class), the IO instance of
--  Alternative (its empty/<|> are exception-based), and asum's
--  Foldable generality (list-only here, as Data.Bits is Int-only).
--
--  Applicative itself (with liftA2, *>, <*), <$> and <$ live in the
--  Prelude and are re-exported here as base's export list has them.

infixl 3 <|>
infixl 4 <**>

--  Alternative, as base has it: a monoid on applicative functors.
--  some/many: some v is one-or-more, many v is zero-or-more --
--  left as their mutually recursive defaults, so they terminate
--  exactly where base's do (parsers that consume input) and diverge
--  where base's diverge (e.g. some (Just x)).
class Applicative f => Alternative f where
  empty :: f a
  (<|>) :: f a -> f a -> f a
  some :: f a -> f [a]
  some v = liftA2 (:) v (many v)
  many :: f a -> f [a]
  many v = some v <|> pure []

instance Alternative Maybe where
  empty = Nothing
  Nothing <|> r = r
  l <|> _ = l

instance Alternative [] where
  empty = []
  xs <|> ys = xs ++ ys

--  Const: the functor that ignores its second argument.
newtype Const a b = Const { getConst :: a }
  deriving (Eq, Ord)

instance Functor (Const a) where
  fmap _ (Const x) = Const x

instance Monoid a => Applicative (Const a) where
  pure _ = Const mempty
  Const f <*> Const v = Const (f <> v)

--  WrappedMonad: any Monad, seen through its Applicative face.
newtype WrappedMonad m a = WrapMonad { unwrapMonad :: m a }

instance Monad m => Functor (WrappedMonad m) where
  fmap f (WrapMonad m) = WrapMonad (m >>= \x -> return (f x))

instance Monad m => Applicative (WrappedMonad m) where
  pure x = WrapMonad (return x)
  WrapMonad mf <*> WrapMonad mx =
    WrapMonad (mf >>= \f -> mx >>= \x -> return (f x))

instance Monad m => Monad (WrappedMonad m) where
  return x = WrapMonad (return x)
  WrapMonad m >>= k = WrapMonad (m >>= \x -> unwrapMonad (k x))

--  ZipList: the other Applicative on lists (pointwise, not
--  cartesian). pure repeats forever, per the applicative laws.
newtype ZipList a = ZipList { getZipList :: [a] }
  deriving (Show, Eq, Ord)

instance Functor ZipList where
  fmap f (ZipList xs) = ZipList (map f xs)

instance Applicative ZipList where
  pure x = ZipList (repeat x)
  ZipList fs <*> ZipList xs = ZipList (zipWith (\f x -> f x) fs xs)

instance Alternative ZipList where
  empty = ZipList []
  ZipList xs <|> ZipList ys =
    ZipList (xs ++ drop (length xs) ys)

(<**>) :: Applicative f => f a -> f (a -> b) -> f b
(<**>) = liftA2 (\a f -> f a)

liftA :: Applicative f => (a -> b) -> f a -> f b
liftA f a = pure f <*> a

liftA3 :: Applicative f => (a -> b -> c -> d) -> f a -> f b -> f c -> f d
liftA3 f a b c = liftA2 f a b <*> c

--  One-or-none.
optional :: Alternative f => f a -> f (Maybe a)
optional v = (Just <$> v) <|> pure Nothing

--  The alternative of a list of alternatives (base's is Foldable).
asum :: Alternative f => [f a] -> f a
asum = foldr (<|>) empty
