module Data.Map.Strict
  ( Map, empty, singleton, null, size, member, notMember
  , lookup, findWithDefault, insert, insertWith, insertWithKey, delete
  , adjust, adjustWithKey, alter, update
  , union, unionWith, unionsWith, fromList, fromListWith
  , fromListWithKey, fromDistinctAscList
  , toList, toAscList, keys, elems
  , map, mapWithKey, filter, foldrWithKey, foldlWithKey, foldr', foldl'
  , keysSet
  ) where

-- Value-strict variants (M142): the SAME Map type as Data.Map, so the
-- two mix freely, as in containers. Strict = the stored value is in
-- WHNF.

import Prelude hiding (lookup, map, filter, null)
import Data.Map hiding (singleton, insert, insertWith, insertWithKey,
                        adjust, adjustWithKey, alter, update,
                        fromList, fromListWith, fromListWithKey,
                        map, mapWithKey, unionWith, unionsWith)
import qualified Data.Map as L

singleton :: k -> a -> Map k a
singleton k v = v `seq` L.singleton k v

insert :: Ord k => k -> a -> Map k a -> Map k a
insert k v m = v `seq` L.insert k v m

insertWith :: Ord k => (a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWith f k new m = case L.lookup k m of
  Nothing  -> insert k new m
  Just old -> insert k (f new old) m

insertWithKey :: Ord k => (k -> a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWithKey f k = insertWith (f k) k

adjust :: Ord k => (a -> a) -> k -> Map k a -> Map k a
adjust f k m = case L.lookup k m of
  Nothing -> m
  Just v  -> insert k (f v) m

adjustWithKey :: Ord k => (k -> a -> a) -> k -> Map k a -> Map k a
adjustWithKey f k = adjust (f k) k

alter :: Ord k => (Maybe a -> Maybe a) -> k -> Map k a -> Map k a
alter f k m = case f (L.lookup k m) of
  Nothing -> L.delete k m
  Just v  -> insert k v m

update :: Ord k => (a -> Maybe a) -> k -> Map k a -> Map k a
update f k m = case L.lookup k m of
  Nothing -> m
  Just v  -> case f v of
    Nothing -> L.delete k m
    Just v' -> insert k v' m

fromList :: Ord k => [(k, a)] -> Map k a
fromList = foldl (\m (k, v) -> insert k v m) L.empty

fromListWith :: Ord k => (a -> a -> a) -> [(k, a)] -> Map k a
fromListWith f = foldl (\m (k, v) -> insertWith f k v m) L.empty

fromListWithKey :: Ord k => (k -> a -> a -> a) -> [(k, a)] -> Map k a
fromListWithKey f = foldl (\m (k, v) -> insertWith (f k) k v m) L.empty

map :: (a -> b) -> Map k a -> Map k b
map f = mapWithKey (\_ v -> f v)

mapWithKey :: (k -> a -> b) -> Map k a -> Map k b
mapWithKey f m =
  let r = L.mapWithKey f m
  in L.foldrWithKey (\_ v acc -> v `seq` acc) r r

unionWith :: Ord k => (a -> a -> a) -> Map k a -> Map k a -> Map k a
unionWith f a b = L.foldrWithKey (\k v m -> insertWith f k v m) b a

unionsWith :: Ord k => (a -> a -> a) -> [Map k a] -> Map k a
unionsWith f = foldl (unionWith f) L.empty
