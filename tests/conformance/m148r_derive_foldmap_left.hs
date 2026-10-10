{-# LANGUAGE DeriveFoldable #-}
data Sn a = Nil | Snoc (Sn a) a deriving Foldable
newtype L a = L (Maybe a)
instance Semigroup (L a) where
  a <> L Nothing = a
  _ <> b = b
instance Monoid (L a) where mempty = L Nothing
infS :: Int -> Sn Int
infS n = Snoc (infS (n+1)) n
main :: IO ()
main = do
  let L r = foldMap (L . Just) (infS 0) in print r
  print (foldl (\_ x -> x) (-1) (infS 0))
