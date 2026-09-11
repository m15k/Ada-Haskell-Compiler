module Data.Either
  ( Either (..)
  , either
  , lefts, rights, partitionEithers
  , isLeft, isRight
  , fromLeft, fromRight
  ) where

--  `Either` and `either` are the Prelude's; this module re-exports
--  them beside the selectors base keeps here, so a program that
--  imports Data.Either and nothing else has the whole type.

lefts :: [Either a b] -> [a]
lefts xs = [a | Left a <- xs]

rights :: [Either a b] -> [b]
rights xs = [b | Right b <- xs]

--  One pass, lazily in the accumulator, so it works on a long list
--  the way base's foldr version does.
partitionEithers :: [Either a b] -> ([a], [b])
partitionEithers = foldr step ([], [])
  where
    step (Left a)  (as, bs) = (a : as, bs)
    step (Right b) (as, bs) = (as, b : bs)

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft (Right _) = False

isRight :: Either a b -> Bool
isRight (Left _) = False
isRight (Right _) = True

--  The default is returned for the OTHER constructor.
fromLeft :: a -> Either a b -> a
fromLeft _ (Left a) = a
fromLeft d (Right _) = d

fromRight :: b -> Either a b -> b
fromRight d (Left _) = d
fromRight _ (Right b) = b
