module Data.Stack ( Stack(..), push, pop, size, module Data.Stack ) where

import Data.List (foldl', sortBy)
import qualified Data.Map as M
import Prelude hiding (lookup)

infixr 5 `push`, :<

data Stack a = Empty | a :< (Stack a)
             | Node { item :: !a, rest :: Stack a }
  deriving (Show, Eq)

newtype Size = Size Int deriving Show

type Pair a = (a, Stack a)

class Container f where
  empty :: f a
  insert :: a -> f a -> f a

instance Eq a => Container Stack where
  empty = Empty
  insert = push

push :: a -> Stack a -> Stack a
push x s = x :< s

pop :: Stack a -> Maybe (Pair a)
pop Empty = Nothing
pop (x :< s) = Just (x, s)

size :: Stack a -> Int
size = go 0
  where go n Empty = n
        go n (_ :< s) = go (n + 1) s

classify x
  | x < 0 = "neg"
  | x == 0 = "zero"
  | otherwise = "pos"

main :: IO ()
main = do
  let s = push 1 (push 2 Empty)
  print (size s)
  mapM_ print [ x * y | x <- [1 .. 10], y <- [1, 3 .. 20], x /= y ]
