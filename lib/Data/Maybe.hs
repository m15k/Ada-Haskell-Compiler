module Data.Maybe
  ( maybe, fromMaybe, isJust, isNothing, fromJust
  , listToMaybe, maybeToList, catMaybes, mapMaybe
  ) where

fromJust :: Maybe a -> a
fromJust (Just x) = x
fromJust Nothing  = error "Maybe.fromJust: Nothing"

listToMaybe :: [a] -> Maybe a
listToMaybe []      = Nothing
listToMaybe (x : _) = Just x

maybeToList :: Maybe a -> [a]
maybeToList Nothing  = []
maybeToList (Just x) = [x]

catMaybes :: [Maybe a] -> [a]
catMaybes xs = [x | Just x <- xs]

mapMaybe :: (a -> Maybe b) -> [a] -> [b]
mapMaybe f xs = catMaybes (map f xs)
