module Data.Map
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

-- containers' Data.Map (= Data.Map.Lazy): a weight-balanced binary
-- search tree, in Data.Map.Internal (shared with Data.Map.Strict, so
-- the two mix freely). Everything observable - toList order, Show
-- format, union bias, key identity on duplicates, error texts -
-- matches containers-0.6.7; conformance tests oracle against it. The
-- names that collide with the Prelude (lookup, map, filter, foldr,
-- take, ...) are meant to be imported qualified, as with containers.

import Prelude ()
import Data.Map.Internal
