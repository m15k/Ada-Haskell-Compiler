{-# LANGUAGE DeriveFunctor, DeriveFoldable, DeriveTraversable, EmptyDataDeriving #-}
data V a deriving (Functor, Foldable, Traversable)
main :: IO ()
main = do
  print (length ([] :: [V Int]))
  print (null (fmap id ([] :: [V Int])))
