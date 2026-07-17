module Stack (Stack, push, pop, empty, size) where

data Stack = Stack [Int]

empty :: Stack
empty = Stack []

push :: Int -> Stack -> Stack
push x (Stack xs) = Stack (x : xs)

pop :: Stack -> (Maybe Int, Stack)
pop (Stack [])       = (Nothing, Stack [])
pop (Stack (x : xs)) = (Just x, Stack xs)

size :: Stack -> Int
size (Stack xs) = length xs
