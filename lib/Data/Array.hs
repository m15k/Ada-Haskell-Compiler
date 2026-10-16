module Data.Array
  ( Array, array, listArray, (!), bounds, indices, elems, assocs
  , (//)
  ) where

import Data.Ix (index)
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
      fromMaybe (errorWithoutStackTrace "(Array.!): undefined array element")
        (lookup i ivsSorted)
    ivsSorted = sortOn fst ivs

listArray :: (Int, Int) -> [e] -> Array e
listArray (lo, hi) es = MkArray (lo, hi) (take (hi - lo + 1) es)

-- Out of range is the index type's Ix error, as GHC's (!) reports it:
-- Ix{Int}.index: Index (5) out of range ((0,2)).
(!) :: Array e -> Int -> e
(!) (MkArray b es) i = pickAt es (index b i)

pickAt :: [e] -> Int -> e
pickAt (x : _) 0 = x
pickAt (_ : xs) n = pickAt xs (n - 1)
pickAt [] _ = errorWithoutStackTrace "(Array.!): undefined array element"

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

--  base's instances over the elements, in index order (M150).
instance Functor Array where
  fmap f (MkArray b es) = MkArray b (map f es)

instance Foldable Array where
  foldr f z (MkArray _ es) = foldr f z es
  null (MkArray _ es) = null es
  length (MkArray _ es) = length es

instance Traversable Array where
  traverse f (MkArray b es) = fmap (MkArray b) (traverse f es)
