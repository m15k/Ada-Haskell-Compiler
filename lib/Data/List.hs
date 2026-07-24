module Data.List
  ( sort, sortBy, sortOn, insert, insertBy
  , nub, nubBy, delete, deleteBy, (\\), union, intersect
  , group, groupBy, partition
  , find, findIndex, elemIndex, elemIndices, findIndices
  , isPrefixOf, isSuffixOf, isInfixOf
  , transpose, intercalate, intersperse
  , subsequences, permutations
  , zip3, zipWith3, unzip3
  , scanl, scanl1, scanr, scanr1
  , tails, inits
  , maximumBy, minimumBy
  , foldl', genericLength
  , lookup
  ) where

import Data.Ord (comparing)

infix 5 \\

sort :: Ord a => [a] -> [a]
sort xs = sortBy compare xs

--  Stable merge sort: with a stable algorithm the result is unique,
--  so it matches base's (smarter) mergesort output exactly.
sortBy :: (a -> a -> Ordering) -> [a] -> [a]
sortBy _ [] = []
sortBy _ [x] = [x]
sortBy cmp xs = mergeSB cmp (sortBy cmp as) (sortBy cmp bs)
  where
    (as, bs) = splitAt (div (length xs) 2) xs

mergeSB :: (a -> a -> Ordering) -> [a] -> [a] -> [a]
mergeSB _ [] ys = ys
mergeSB _ xs [] = xs
mergeSB cmp (x : xs) (y : ys) =
  if cmp x y == GT
    then y : mergeSB cmp (x : xs) ys
    else x : mergeSB cmp xs (y : ys)

sortOn :: Ord b => (a -> b) -> [a] -> [a]
sortOn f xs = sortBy (comparing f) xs

insert :: Ord a => a -> [a] -> [a]
insert x xs = insertBy compare x xs

insertBy :: (a -> a -> Ordering) -> a -> [a] -> [a]
insertBy _ x [] = [x]
insertBy cmp x (y : ys) =
  case cmp x y of
    GT -> y : insertBy cmp x ys
    _  -> x : y : ys

nub :: Eq a => [a] -> [a]
nub xs = nubBy (==) xs

nubBy :: (a -> a -> Bool) -> [a] -> [a]
nubBy _ [] = []
nubBy eq (x : xs) = x : nubBy eq (filter (\y -> not (eq x y)) xs)

delete :: Eq a => a -> [a] -> [a]
delete x xs = deleteBy (==) x xs

deleteBy :: (a -> a -> Bool) -> a -> [a] -> [a]
deleteBy _ _ [] = []
deleteBy eq x (y : ys) =
  if eq x y then ys else y : deleteBy eq x ys

(\\) :: Eq a => [a] -> [a] -> [a]
(\\) xs ys = foldl (flip delete) xs ys

union :: Eq a => [a] -> [a] -> [a]
union xs ys = xs ++ foldl (flip delete) (nub ys) xs

intersect :: Eq a => [a] -> [a] -> [a]
intersect xs ys = [x | x <- xs, elem x ys]

group :: Eq a => [a] -> [[a]]
group xs = groupBy (==) xs

groupBy :: (a -> a -> Bool) -> [a] -> [[a]]
groupBy _ [] = []
groupBy eq (x : xs) = (x : ys) : groupBy eq zs
  where
    (ys, zs) = span (eq x) xs

partition :: (a -> Bool) -> [a] -> ([a], [a])
partition p xs = (filter p xs, filter (\x -> not (p x)) xs)

find :: (a -> Bool) -> [a] -> Maybe a
find _ [] = Nothing
find p (x : xs) = if p x then Just x else find p xs

findIndex :: (a -> Bool) -> [a] -> Maybe Int
findIndex p xs = goFI p xs 0

goFI :: (a -> Bool) -> [a] -> Int -> Maybe Int
goFI _ [] _ = Nothing
goFI p (y : ys) n = if p y then Just n else goFI p ys (n + 1)

elemIndex :: Eq a => a -> [a] -> Maybe Int
elemIndex x xs = findIndex (== x) xs

findIndices :: (a -> Bool) -> [a] -> [Int]
findIndices p xs = [i | (i, x) <- zip [0 ..] xs, p x]

elemIndices :: Eq a => a -> [a] -> [Int]
elemIndices x xs = findIndices (== x) xs

isPrefixOf :: Eq a => [a] -> [a] -> Bool
isPrefixOf [] _ = True
isPrefixOf _ [] = False
isPrefixOf (x : xs) (y : ys) = x == y && isPrefixOf xs ys

isSuffixOf :: Eq a => [a] -> [a] -> Bool
isSuffixOf xs ys = isPrefixOf (reverse xs) (reverse ys)

isInfixOf :: Eq a => [a] -> [a] -> Bool
isInfixOf xs ys = any (isPrefixOf xs) (tails ys)

transpose :: [[a]] -> [[a]]
transpose [] = []
transpose ([] : xss) = transpose xss
transpose ((x : xs) : xss) =
  (x : [h | (h : _) <- xss]) : transpose (xs : [t | (_ : t) <- xss])

intersperse :: a -> [a] -> [a]
intersperse _ [] = []
intersperse _ [x] = [x]
intersperse s (x : xs) = x : s : intersperse s xs

intercalate :: [a] -> [[a]] -> [a]
intercalate s xss = concat (intersperse s xss)

--  base's exact production order.
subsequences :: [a] -> [[a]]
subsequences xs = [] : nonEmptySubsequences xs

nonEmptySubsequences :: [a] -> [[a]]
nonEmptySubsequences [] = []
nonEmptySubsequences (x : xs) =
  [x] : foldr fNES [] (nonEmptySubsequences xs)
  where
    fNES ys r = ys : (x : ys) : r

--  base's exact production order (the interleave scheme).
permutations :: [a] -> [[a]]
permutations xs0 = xs0 : perms xs0 []
  where
    perms [] _ = []
    perms (t : ts) is =
      foldr interleave (perms ts (t : is)) (permutations is)
      where
        interleave ys r = snd (interleave2 (\l -> l) ys r)
        interleave2 _ [] r = (ts, r)
        interleave2 f (y : ys) r =
          case interleave2 (\l -> f (y : l)) ys r of
            (us, zs) -> (y : us, f (t : y : us) : zs)

zip3 :: [a] -> [b] -> [c] -> [(a, b, c)]
zip3 (a : as) (b : bs) (c : cs) = (a, b, c) : zip3 as bs cs
zip3 _ _ _ = []

zipWith3 :: (a -> b -> c -> d) -> [a] -> [b] -> [c] -> [d]
zipWith3 f (a : as) (b : bs) (c : cs) =
  f a b c : zipWith3 f as bs cs
zipWith3 _ _ _ _ = []

unzip3 :: [(a, b, c)] -> ([a], [b], [c])
unzip3 xs =
  ( [a | (a, _, _) <- xs]
  , [b | (_, b, _) <- xs]
  , [c | (_, _, c) <- xs]
  )

scanl :: (b -> a -> b) -> b -> [a] -> [b]
scanl f z xs =
  z : case xs of
        []      -> []
        (x : r) -> scanl f (f z x) r

scanl1 :: (a -> a -> a) -> [a] -> [a]
scanl1 _ [] = []
scanl1 f (x : xs) = scanl f x xs

scanr :: (a -> b -> b) -> b -> [a] -> [b]
scanr _ z [] = [z]
scanr f z (x : xs) = f x (head qs) : qs
  where
    qs = scanr f z xs

scanr1 :: (a -> a -> a) -> [a] -> [a]
scanr1 _ [] = []
scanr1 _ [x] = [x]
scanr1 f (x : xs) = f x (head qs) : qs
  where
    qs = scanr1 f xs

tails :: [a] -> [[a]]
tails [] = [[]]
tails (x : xs) = (x : xs) : tails xs

inits :: [a] -> [[a]]
inits [] = [[]]
inits (x : xs) = [] : map (\ys -> x : ys) (inits xs)

maximumBy :: (a -> a -> Ordering) -> [a] -> a
maximumBy _ [] = error "List.maximumBy: empty list"
maximumBy cmp xs = foldl1 (pickMax cmp) xs

pickMax :: (a -> a -> Ordering) -> a -> a -> a
pickMax cmp a b = if cmp a b == LT then b else a

minimumBy :: (a -> a -> Ordering) -> [a] -> a
minimumBy _ [] = error "List.minimumBy: empty list"
minimumBy cmp xs = foldl1 (pickMin cmp) xs

pickMin :: (a -> a -> Ordering) -> a -> a -> a
pickMin cmp a b = if cmp a b == GT then b else a

--  Accumulator fold; observable behavior matches foldl (AHC has no
--  seq), with the large runtime stack absorbing chain depth.
foldl' :: (b -> a -> b) -> b -> [a] -> b
foldl' _ z [] = z
foldl' f z (x : xs) = let z' = f z x in z' `seq` foldl' f z' xs

genericLength :: Num n => [a] -> n
genericLength [] = 0
genericLength (_ : xs) = 1 + genericLength xs
