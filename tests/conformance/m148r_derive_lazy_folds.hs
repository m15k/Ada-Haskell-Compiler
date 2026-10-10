{-# LANGUAGE DeriveFunctor, DeriveFoldable, DeriveTraversable #-}
import Data.Foldable (toList, foldl')
data Tree a = Leaf | Node (Tree a) a (Tree a) deriving (Show, Functor, Foldable, Traversable)
data Str a = Cons a (Str a) deriving (Functor, Foldable)
nats :: Int -> Str Int
nats n = Cons n (nats (n+1))
right :: Int -> Tree Int
right n = Node Leaf n (right (n+1))
main :: IO ()
main = do
  print (take 3 (toList (nats 0)))
  print (take 3 (toList (right 0)))
  print (foldr (\_ _ -> True) False (Node Leaf 1 undefined))
  print (null (Node undefined (1::Int) undefined))
  print (null (Cons (1::Int) undefined))
  print (elem 5 (nats 0))
  print (any (>3) (right 0))
  print (foldMap (\x -> [x]) (Node (Node Leaf 1 Leaf) 2 (Node Leaf 3 Leaf)))
  print (foldl (flip (:)) [] (Node (Node Leaf 1 Leaf) 2 (Node Leaf 3 Leaf)))
  print (foldr' (+) 0 (Node (Node Leaf 1 Leaf) 2 (Node Leaf 3 Leaf)))
  print (length (Node (Node Leaf 1 Leaf) 2 (Node Leaf 3 Leaf)), sum (Node Leaf 4 Leaf), product (Node Leaf 4 Leaf))
  print (maximum (Node (Node Leaf 1 Leaf) 9 (Node Leaf 3 Leaf)), minimum (Node (Node Leaf 1 Leaf) 9 (Node Leaf 3 Leaf)))
  print (null (Leaf :: Tree Int), length (Leaf :: Tree Int))
  print (fmap show (Node (Node Leaf 1 Leaf) 2 Leaf))
  print (foldr1 (-) (Node (Node Leaf 10 Leaf) 3 (Node Leaf 1 Leaf)), foldl1 (-) (Node (Node Leaf 10 Leaf) 3 (Node Leaf 1 Leaf)))
  print (foldl' (+) 0 (Node Leaf 4 Leaf))
  print (sequenceA (Node Leaf [1,2] (Node Leaf [3,4] Leaf)))
  print (head (toList (Node (right 0) 99 Leaf)))
  where foldr' = foldr
