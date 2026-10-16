-- base: class (Functor t, Foldable t) => Traversable t. A Traversable
-- instance without a Foldable instance is rejected (M150).
data Pair a = Pair a a

instance Functor Pair where
  fmap f (Pair x y) = Pair (f x) (f y)

instance Traversable Pair where
  traverse f (Pair x y) = Pair <$> f x <*> f y

main :: IO ()
main = print (fmap (const ()) (Pair 1 2) `seq` ())
