module Data.Maybe
  ( maybe, fromMaybe, isJust, isNothing, fromJust
  , listToMaybe, maybeToList, catMaybes, mapMaybe
  ) where

-- fromJust is the Prelude's own (not in the user Prelude's export
-- list), re-exported here: one entity, so a user's use of it is
-- located like head's (M149).

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
