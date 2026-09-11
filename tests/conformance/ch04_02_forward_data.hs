-- Report 4.2.1: the type declarations of a module are mutually
-- recursive, so a constructor field may name a type declared later
-- in the file, at any kind.
module Main where

data Value = VNil
           | VArr [Value]
           | VObj [Member]          -- forward, declared below
           | VBox (Box Int)         -- forward, kind * -> *
           | VPair (Twin Bool)      -- forward through a synonym

data Member = Member String Value

data Box a = Box a

type Twin a = Box (Pair a a)        -- synonym over a later data type

data Pair a b = Pair a b

-- Mutual recursion in the other direction as well.
data Tree a = Leaf a | Node (Forest a)
data Forest a = Forest [Tree a]

size :: Value -> Int
size VNil = 1
size (VArr vs) = 1 + sum (map size vs)
size (VObj ms) = 1 + sum (map (\(Member _ v) -> size v) ms)
size (VBox (Box _)) = 2
size (VPair (Box (Pair _ _))) = 3

flatten :: Tree a -> [a]
flatten (Leaf a) = [a]
flatten (Node (Forest ts)) = concatMap flatten ts

main :: IO ()
main = do
  print (size (VObj [Member "a" (VArr [VNil, VNil]), Member "b" VNil]))
  print (size (VBox (Box 7)))
  print (size (VPair (Box (Pair True False))))
  print (flatten (Node (Forest [Leaf 1, Node (Forest [Leaf 2, Leaf 3])])))
