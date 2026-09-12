module Data.Foldable
  ( Foldable (..)
  , toList
  , foldr', foldl'
  , notElem, concat, concatMap
  , and, or, any, all
  , foldr1, foldl1
  , mapM_, forM_, sequence_
  , find
  ) where

--  The class itself and every Foldable-general function the Prelude
--  exports live in the Prelude (Report 9.1's shape: base exports the
--  class and most of its API from Prelude, and keeps `toList`, the
--  strict folds and `find` here). This module is the facade that
--  gathers them, plus the ones the Prelude deliberately does not
--  export - `toList` above all, which would otherwise shadow every
--  program's own.

toList :: Foldable t => t a -> [a]
toList t = foldr (:) [] t

--  Strict in the accumulator, like Data.List.foldl'.
foldl' :: Foldable t => (b -> a -> b) -> b -> t a -> b
foldl' f z t = go z (toList t)
  where
    go acc [] = acc
    go acc (x : xs) = let acc' = f acc x in acc' `seq` go acc' xs

foldr' :: Foldable t => (a -> b -> b) -> b -> t a -> b
foldr' f z t = foldl' (flip f) z (reverse (toList t))

find :: Foldable t => (a -> Bool) -> t a -> Maybe a
find p t = go (toList t)
  where
    go [] = Nothing
    go (x : xs) = if p x then Just x else go xs

forM_ :: (Foldable t, Monad m) => t a -> (a -> m b) -> m ()
forM_ t f = mapM_ f t
