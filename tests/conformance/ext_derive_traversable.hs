{-# LANGUAGE DeriveFunctor, DeriveFoldable, DeriveTraversable #-}
-- Stock DeriveTraversable, always on in AHC (M148): effect order.
data Tree a = Leaf | Node (Tree a) a (Tree a) deriving (Show, Functor, Foldable, Traversable)
data Two a = Two a [a] (Maybe a) deriving (Show, Functor, Foldable, Traversable)

t :: Tree Int
t = Node (Node Leaf 1 Leaf) 2 (Node Leaf 3 Leaf)

safeHalf :: Int -> Maybe Int
safeHalf n = if even n then Just (n `div` 2) else Nothing

main :: IO ()
main = do
  print (traverse safeHalf (fmap (* 2) t), traverse safeHalf t)
  print (traverse (\x -> [x, x + 10]) (Two 1 [2] (Just 3)))
  r <- traverse (\x -> do { print x; return (x * x) }) t
  print r
  print (sequenceA (Two (Just 1) [Just 2] Nothing), sequenceA (Two [1, 2] [] Nothing))
  mapM_ print (Two 'a' "bc" (Just 'd'))
