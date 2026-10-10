{-# LANGUAGE DeriveFunctor, DeriveFoldable #-}
data T f b a = T (f b a) Int deriving (Functor, Foldable)
main :: IO ()
main = do
  let T e n = fmap (+1) (T (Right 1 :: Either String Int) 3)
  print (e, n, sum (T (Right 5 :: Either String Int) 0))
