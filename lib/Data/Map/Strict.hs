module Data.Map.Strict
  ( Map
  -- construction
  , empty, singleton, fromList, fromListWith, fromListWithKey
  , fromAscList, fromAscListWith, fromAscListWithKey
  , fromDistinctAscList, fromDescList, fromDistinctDescList
  -- insertion, deletion, update
  , insert, insertWith, insertWithKey, insertLookupWithKey
  , delete, adjust, adjustWithKey, update, updateWithKey
  , updateLookupWithKey, alter
  -- query
  , lookup, (!?), (!), findWithDefault, member, notMember
  , lookupLT, lookupGT, lookupLE, lookupGE, null, size
  -- combine
  , union, unionWith, unionWithKey, unions, unionsWith
  , difference, (\\), differenceWith
  , intersection, intersectionWith, intersectionWithKey
  , disjoint, isSubmapOf, isSubmapOfBy
  -- traversal
  , map, mapWithKey, traverseWithKey, mapAccum, mapAccumWithKey
  , mapKeys, mapKeysWith, mapKeysMonotonic
  -- folds
  , foldr, foldl, foldrWithKey, foldlWithKey, foldMapWithKey
  , foldr', foldl', foldrWithKey', foldlWithKey'
  -- conversion
  , elems, keys, assocs, keysSet, toList, toAscList, toDescList
  -- filter
  , filter, filterWithKey, restrictKeys, withoutKeys
  , partition, partitionWithKey, mapMaybe, mapMaybeWithKey
  , mapEither, mapEitherWithKey
  , split, splitLookup
  -- indexed
  , lookupIndex, findIndex, elemAt, deleteAt, take, drop, splitAt
  -- min/max
  , lookupMin, lookupMax, findMin, findMax, deleteMin, deleteMax
  , deleteFindMin, deleteFindMax, minView, maxView
  , minViewWithKey, maxViewWithKey
  , valid
  ) where

-- containers' Data.Map.Strict (M142): the SAME Map type as Data.Map,
-- so the two mix freely. Every function that stores a value it was
-- handed or computed forces it to WHNF first; the structure-only
-- operations are Data.Map's own. Transcribed from containers-0.6.7's
-- Data.Map.Strict.Internal, so key identity matches the lazy module's.

import Prelude hiding (lookup, map, filter, null, foldr, foldl, take,
                       drop, splitAt)
import Data.Map.Internal hiding
  ( singleton, fromList, fromListWith, fromListWithKey
  , fromAscList, fromAscListWith, fromAscListWithKey
  , fromDistinctAscList, fromDescList, fromDistinctDescList
  , insert, insertWith, insertWithKey, insertLookupWithKey
  , adjust, adjustWithKey, update, updateWithKey
  , updateLookupWithKey, alter
  , unionWith, unionWithKey, unionsWith, differenceWith
  , intersectionWith, intersectionWithKey
  , map, mapWithKey, traverseWithKey, mapAccum, mapAccumWithKey, mapKeysWith
  , mapMaybe, mapMaybeWithKey, mapEither, mapEitherWithKey
  , insertWithKeyR )
import qualified Data.Map.Internal as L

singleton :: k -> a -> Map k a
singleton k x = x `seq` Bin 1 k x Tip Tip

insert :: Ord k => k -> a -> Map k a -> Map k a
insert k x m = x `seq` L.insert k x m

insertWith :: Ord k => (a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWith f = insertWithKey (\_ x y -> f x y)

insertWithKey :: Ord k => (k -> a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWithKey _ kx x Tip = singleton kx x
insertWithKey f kx x (Bin sy ky y l r) = case compare kx ky of
  LT -> balanceL ky y (insertWithKey f kx x l) r
  GT -> balanceR ky y l (insertWithKey f kx x r)
  EQ -> let x' = f kx x y in x' `seq` Bin sy kx x' l r

insertWithKeyR :: Ord k => (k -> a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWithKeyR _ kx x Tip = singleton kx x
insertWithKeyR f kx x (Bin sy ky y l r) = case compare kx ky of
  LT -> balanceL ky y (insertWithKeyR f kx x l) r
  GT -> balanceR ky y l (insertWithKeyR f kx x r)
  EQ -> let y' = f ky y x in y' `seq` Bin sy ky y' l r

insertLookupWithKey :: Ord k => (k -> a -> a -> a) -> k -> a -> Map k a
                    -> (Maybe a, Map k a)
insertLookupWithKey f kx x m = (L.lookup kx m, insertWithKey f kx x m)

adjust :: Ord k => (a -> a) -> k -> Map k a -> Map k a
adjust f = adjustWithKey (\_ x -> f x)

adjustWithKey :: Ord k => (k -> a -> a) -> k -> Map k a -> Map k a
adjustWithKey _ _ Tip = Tip
adjustWithKey f k (Bin sx kx x l r) = case compare k kx of
  LT -> Bin sx kx x (adjustWithKey f k l) r
  GT -> Bin sx kx x l (adjustWithKey f k r)
  EQ -> let x' = f kx x in x' `seq` Bin sx kx x' l r

update :: Ord k => (a -> Maybe a) -> k -> Map k a -> Map k a
update f = updateWithKey (\_ x -> f x)

updateWithKey :: Ord k => (k -> a -> Maybe a) -> k -> Map k a -> Map k a
updateWithKey _ _ Tip = Tip
updateWithKey f k (Bin sx kx x l r) = case compare k kx of
  LT -> balanceR kx x (updateWithKey f k l) r
  GT -> balanceL kx x l (updateWithKey f k r)
  EQ -> case f kx x of
          Just x' -> x' `seq` Bin sx kx x' l r
          Nothing -> glue l r

updateLookupWithKey :: Ord k => (k -> a -> Maybe a) -> k -> Map k a
                    -> (Maybe a, Map k a)
updateLookupWithKey f k m = case L.lookupLE k m of
  Just (kx, x) | not (k < kx) && not (kx < k) -> case f kx x of
    Just x' -> x' `seq` (Just x', updateWithKey f k m)
    Nothing -> (Just x, delete k m)
  _ -> (Nothing, m)

alter :: Ord k => (Maybe a -> Maybe a) -> k -> Map k a -> Map k a
alter f k Tip = case f Nothing of
  Nothing -> Tip
  Just x  -> singleton k x
alter f k (Bin sx kx x l r) = case compare k kx of
  LT -> balance kx x (alter f k l) r
  GT -> balance kx x l (alter f k r)
  EQ -> case f (Just x) of
          Just x' -> x' `seq` Bin sx kx x' l r
          Nothing -> glue l r

unionWith :: Ord k => (a -> a -> a) -> Map k a -> Map k a -> Map k a
unionWith f = unionWithKey (\_ x y -> f x y)

unionWithKey :: Ord k => (k -> a -> a -> a) -> Map k a -> Map k a -> Map k a
unionWithKey _ t1 Tip = t1
unionWithKey f t1 (Bin _ k x Tip Tip) = insertWithKeyR f k x t1
unionWithKey f (Bin _ k x Tip Tip) t2 = insertWithKey f k x t2
unionWithKey _ Tip t2 = t2
unionWithKey f (Bin _ k1 x1 l1 r1) t2 = case splitLookup k1 t2 of
  (l2, mb, r2) ->
    let l1l2 = unionWithKey f l1 l2
        r1r2 = unionWithKey f r1 r2
    in case mb of
         Nothing -> link k1 x1 l1l2 r1r2
         Just x2 -> let x1' = f k1 x1 x2 in x1' `seq` link k1 x1' l1l2 r1r2

unionsWith :: Ord k => (a -> a -> a) -> [Map k a] -> Map k a
unionsWith f = foldlStrict (unionWith f) empty

differenceWith :: Ord k => (a -> b -> Maybe a) -> Map k a -> Map k b -> Map k a
differenceWith f t1 t2 = mapMaybeWithKey g t1
  where g k x = case L.lookup k t2 of
          Nothing -> Just x
          Just y  -> f x y

intersectionWith :: Ord k => (a -> b -> c) -> Map k a -> Map k b -> Map k c
intersectionWith f = intersectionWithKey (\_ x y -> f x y)

intersectionWithKey :: Ord k => (k -> a -> b -> c) -> Map k a -> Map k b -> Map k c
intersectionWithKey _ Tip _ = Tip
intersectionWithKey _ _ Tip = Tip
intersectionWithKey f (Bin _ k x1 l1 r1) t2 = case splitLookup k t2 of
  (l2, mb, r2) ->
    let l1l2 = intersectionWithKey f l1 l2
        r1r2 = intersectionWithKey f r1 r2
    in case mb of
         Just x2 -> let x1' = f k x1 x2 in x1' `seq` link k x1' l1l2 r1r2
         Nothing -> link2 l1l2 r1r2

map :: (a -> b) -> Map k a -> Map k b
map f = mapWithKey (\_ x -> f x)

mapWithKey :: (k -> a -> b) -> Map k a -> Map k b
mapWithKey _ Tip = Tip
mapWithKey f (Bin sx kx x l r) =
  -- the subtrees are forced explicitly: containers gets that from
  -- Bin's strict fields
  let x' = f kx x
      l' = mapWithKey f l
      r' = mapWithKey f r
  in x' `seq` l' `seq` r' `seq` Bin sx kx x' l' r'

traverseWithKey :: Applicative t => (k -> a -> t b) -> Map k a -> t (Map k b)
traverseWithKey f = go
  where
    go Tip = pure Tip
    go (Bin s k v l r) =
      pure (\l' v' r' -> v' `seq` Bin s k v' l' r') <*> go l <*> f k v <*> go r

mapAccum :: (a -> b -> (a, c)) -> a -> Map k b -> (a, Map k c)
mapAccum f a m = mapAccumWithKey (\a' _ x' -> f a' x') a m

mapAccumWithKey :: (a -> k -> b -> (a, c)) -> a -> Map k b -> (a, Map k c)
mapAccumWithKey _ a Tip = (a, Tip)
mapAccumWithKey f a (Bin sx kx x l r) =
  case mapAccumWithKey f a l of
    (a1, l') -> case f a1 kx x of
      (a2, x') -> x' `seq` (case mapAccumWithKey f a2 r of
        (a3, r') -> (a3, Bin sx kx x' l' r'))

mapKeysWith :: Ord k2 => (a -> a -> a) -> (k1 -> k2) -> Map k1 a -> Map k2 a
mapKeysWith c f m = fromListWith c (foldrWithKey (\k x xs -> (f k, x) : xs) [] m)

mapMaybe :: (a -> Maybe b) -> Map k a -> Map k b
mapMaybe f = mapMaybeWithKey (\_ x -> f x)

mapMaybeWithKey :: (k -> a -> Maybe b) -> Map k a -> Map k b
mapMaybeWithKey _ Tip = Tip
mapMaybeWithKey f (Bin _ kx x l r) = case f kx x of
  Just y  -> y `seq` link kx y (mapMaybeWithKey f l) (mapMaybeWithKey f r)
  Nothing -> link2 (mapMaybeWithKey f l) (mapMaybeWithKey f r)

mapEither :: (a -> Either b c) -> Map k a -> (Map k b, Map k c)
mapEither f = mapEitherWithKey (\_ x -> f x)

mapEitherWithKey :: (k -> a -> Either b c) -> Map k a -> (Map k b, Map k c)
mapEitherWithKey _ Tip = (Tip, Tip)
mapEitherWithKey f (Bin _ kx x l r) =
  case mapEitherWithKey f l of
    (l1, l2) -> case mapEitherWithKey f r of
      (r1, r2) -> case f kx x of
        Left y  -> y `seq` (link kx y l1 r1, link2 l2 r2)
        Right z -> z `seq` (link2 l1 r1, link kx z l2 r2)

fromList :: Ord k => [(k, a)] -> Map k a
fromList = foldlStrict (\t (k, x) -> insert k x t) Tip

fromListWith :: Ord k => (a -> a -> a) -> [(k, a)] -> Map k a
fromListWith f = fromListWithKey (\_ x y -> f x y)

fromListWithKey :: Ord k => (k -> a -> a -> a) -> [(k, a)] -> Map k a
fromListWithKey f = foldlStrict (\t (k, x) -> insertWithKey f k x t) Tip

fromAscList :: Eq k => [(k, a)] -> Map k a
fromAscList xs = fromAscListWithKey (\_ x _ -> x) xs

fromAscListWith :: Eq k => (a -> a -> a) -> [(k, a)] -> Map k a
fromAscListWith f xs = fromAscListWithKey (\_ x y -> f x y) xs

fromAscListWithKey :: Eq k => (k -> a -> a -> a) -> [(k, a)] -> Map k a
fromAscListWithKey f xs = fromDistinctAscList (combineEqWith f xs)

fromDescList :: Eq k => [(k, a)] -> Map k a
fromDescList xs = fromDistinctAscList (reverse (combineEqWith (\_ x _ -> x) xs))

-- The values are forced (the lazy module's leaves them alone).
fromDistinctAscList :: [(k, a)] -> Map k a
fromDistinctAscList xs = forceValues (L.fromDistinctAscList xs)

fromDistinctDescList :: [(k, a)] -> Map k a
fromDistinctDescList xs = forceValues (L.fromDistinctDescList xs)

forceValues :: Map k a -> Map k a
forceValues m = L.foldr seq () m `seq` m
