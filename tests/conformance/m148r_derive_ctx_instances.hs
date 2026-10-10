{-# LANGUAGE DeriveFunctor, DeriveFoldable, DeriveTraversable #-}
newtype Wrap f a = Wrap (f a) deriving (Show)
instance Functor f => Functor (Wrap f) where fmap g (Wrap x) = Wrap (fmap g x)
data U f g a = U (f (g a)) (Maybe (f a)) deriving (Functor, Foldable, Traversable)
main :: IO ()
main = do
  let U x y = fmap show (U [Just 1, Nothing] (Just [2,3]))
  print (x, y)
  print (sum (U [Just 1, Nothing] (Just [2,3])))
  r <- traverse (\v -> print v >> return v) (U [Just 1, Just 5] (Just [2,3]))
  let U x2 _ = r in print x2
