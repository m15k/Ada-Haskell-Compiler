{-# LANGUAGE DeriveFunctor, DeriveFoldable #-}
-- Stock DeriveFoldable, always on in AHC (M148).
data Tree a = Leaf | Node (Tree a) a (Tree a) deriving (Show, Functor, Foldable)
data Rose a = Rose a [Rose a] deriving (Show, Foldable)
data Mix a = Mix Int a (Maybe a) [a] (Bool, a) deriving Foldable

t :: Tree Int
t = Node (Node Leaf 1 Leaf) 2 (Node Leaf 3 (Node Leaf 4 Leaf))

main :: IO ()
main = do
  print (sum t, product t, length t, maximum t)
  print (minimum t, elem 3 t, null t, null Leaf)
  print (foldr (:) [] t, foldl (flip (:)) [] t, foldr1 (-) t, foldl1 (-) t)
  print (sum (Rose 1 [Rose 2 [Rose 3 []], Rose 4 []]), foldr (:) [] (Mix 0 1 (Just 2) [3, 4] (True, 5)))
  print (concatMap show (Rose 'a' [Rose 'b' []]), foldMap (\x -> [x, x]) t)
