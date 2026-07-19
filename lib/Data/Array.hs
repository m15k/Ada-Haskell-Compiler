module Data.Array
  ( Array, array, listArray, (!), bounds, indices, elems, assocs
  , (//)
  ) where

import Data.List (find, sortOn)
import Data.Maybe (fromMaybe)

infixl 9 !
infixl 9 //

--  Int-indexed, list-backed (indexing is O(n) - documented).
data Array e = MkArray (Int, Int) [e]

array :: (Int, Int) -> [(Int, e)] -> Array e
array (lo, hi) ivs =
  MkArray (lo, hi)
    [ pick i | i <- [lo .. hi] ]
  where
    pick i =
      fromMaybe (error "(Array.!): undefined array element")
        (lookup i ivsSorted)
    ivsSorted = sortOn fst ivs

listArray :: (Int, Int) -> [e] -> Array e
listArray (lo, hi) es = MkArray (lo, hi) (take (hi - lo + 1) es)

(!) :: Array e -> Int -> e
(!) (MkArray (lo, hi) es) i =
  if i < lo || i > hi
    then error "(Array.!): index out of range"
    else pickAt es (i - lo)

pickAt :: [e] -> Int -> e
pickAt (x : _) 0 = x
pickAt (_ : xs) n = pickAt xs (n - 1)
pickAt [] _ = error "(Array.!): undefined array element"

bounds :: Array e -> (Int, Int)
bounds (MkArray b _) = b

indices :: Array e -> [Int]
indices (MkArray (lo, hi) _) = [lo .. hi]

elems :: Array e -> [e]
elems (MkArray _ es) = es

assocs :: Array e -> [(Int, e)]
assocs (MkArray (lo, hi) es) = zip [lo .. hi] es

(//) :: Array e -> [(Int, e)] -> Array e
(//) (MkArray (lo, hi) es) ivs =
  MkArray (lo, hi)
    [ replaceAt i e | (i, e) <- zip [lo .. hi] es ]
  where
    replaceAt i old =
      case find (\p -> fst p == i) ivs of
        Just p  -> snd p
        Nothing -> old

instance Show e => Show (Array e) where
  showsPrec d a =
    showParen (d > 9)
      (\t -> "array " ++ showsPrec 10 (bounds a)
               (" " ++ showsPrec 10 (assocs a) t))

instance Eq e => Eq (Array e) where
  a == b = bounds a == bounds b && elems a == elems b
