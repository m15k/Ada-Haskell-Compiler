{-# LANGUAGE DeriveFunctor, DeriveFoldable, DeriveTraversable #-}
-- Derived methods on a long recursive type stay linear (M148 review:
-- an eta-expanded \y -> f y per level made fmap, foldr and traverse
-- quadratic).
data L a = N | C a (L a) deriving (Functor, Foldable, Traversable)

build :: Int -> L Int
build 0 = N
build n = C n (build (n - 1))

main :: IO ()
main = do
  let l = build 200000
  print (sum l, length l)
  print (sum (fmap (+ 1) l))
  print (fmap length (traverse Just l))
  print (foldr (\x acc -> x + acc) 0 l)
