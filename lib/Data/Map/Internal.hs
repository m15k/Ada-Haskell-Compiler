module Data.Map.Internal where

-- Data.Map's implementation (M142 review round), shared by Data.Map
-- (the lazy API) and Data.Map.Strict (value-strict variants over the
-- SAME type, as containers). Transcribed from containers-0.6.7's
-- Data.Map.Internal: the weight-balanced tree with delta 3 / ratio 2,
-- balanceL/balanceR/link/link2/glue, and the split-based set
-- operations. Following containers exactly also gives its KEY
-- IDENTITY: insert/insertWith store the new key, adjust/alter/update
-- keep the old one, and union/unionWith/intersectionWith keep the
-- left map's key - visible when Eq-equal keys are distinguishable.

import Prelude hiding (lookup, map, filter, null, foldr, foldl, take,
                       drop, splitAt)
import qualified Prelude as P
import qualified Data.Set as Set

infixl 9 !, !?, \\

data Map k a
  = Bin !Int !k a !(Map k a) !(Map k a)
  | Tip

delta :: Int
delta = 3

ratio :: Int
ratio = 2

-------------------------------------------------------------------
-- Construction and queries
-------------------------------------------------------------------

empty :: Map k a
empty = Tip

singleton :: k -> a -> Map k a
singleton k x = Bin 1 k x Tip Tip

null :: Map k a -> Bool
null Tip = True
null _   = False

size :: Map k a -> Int
size Tip = 0
size (Bin s _ _ _ _) = s

lookup :: Ord k => k -> Map k a -> Maybe a
lookup _ Tip = Nothing
lookup k (Bin _ kx x l r) = case compare k kx of
  LT -> lookup k l
  GT -> lookup k r
  EQ -> Just x

(!?) :: Ord k => Map k a -> k -> Maybe a
m !? k = lookup k m

(!) :: Ord k => Map k a -> k -> a
m ! k = case lookup k m of
  Just x  -> x
  Nothing -> error "Map.!: given key is not an element in the map"

member :: Ord k => k -> Map k a -> Bool
member k m = case lookup k m of
  Just _  -> True
  Nothing -> False

notMember :: Ord k => k -> Map k a -> Bool
notMember k m = not (member k m)

findWithDefault :: Ord k => a -> k -> Map k a -> a
findWithDefault d k m = case lookup k m of
  Just x  -> x
  Nothing -> d

lookupLT :: Ord k => k -> Map k v -> Maybe (k, v)
lookupLT = goNothing
  where
    goNothing _ Tip = Nothing
    goNothing x (Bin _ kx vx l r)
      | x <= kx   = goNothing x l
      | otherwise = goJust x kx vx r
    goJust _ kx' x' Tip = Just (kx', x')
    goJust x kx' x' (Bin _ kx vx l r)
      | x <= kx   = goJust x kx' x' l
      | otherwise = goJust x kx vx r

lookupGT :: Ord k => k -> Map k v -> Maybe (k, v)
lookupGT = goNothing
  where
    goNothing _ Tip = Nothing
    goNothing x (Bin _ kx vx l r)
      | x < kx    = goJust x kx vx l
      | otherwise = goNothing x r
    goJust _ kx' x' Tip = Just (kx', x')
    goJust x kx' x' (Bin _ kx vx l r)
      | x < kx    = goJust x kx vx l
      | otherwise = goJust x kx' x' r

lookupLE :: Ord k => k -> Map k v -> Maybe (k, v)
lookupLE = goNothing
  where
    goNothing _ Tip = Nothing
    goNothing x (Bin _ kx vx l r) = case compare x kx of
      LT -> goNothing x l
      EQ -> Just (kx, vx)
      GT -> goJust x kx vx r
    goJust _ kx' x' Tip = Just (kx', x')
    goJust x kx' x' (Bin _ kx vx l r) = case compare x kx of
      LT -> goJust x kx' x' l
      EQ -> Just (kx, vx)
      GT -> goJust x kx vx r

lookupGE :: Ord k => k -> Map k v -> Maybe (k, v)
lookupGE = goNothing
  where
    goNothing _ Tip = Nothing
    goNothing x (Bin _ kx vx l r) = case compare x kx of
      LT -> goJust x kx vx l
      EQ -> Just (kx, vx)
      GT -> goNothing x r
    goJust _ kx' x' Tip = Just (kx', x')
    goJust x kx' x' (Bin _ kx vx l r) = case compare x kx of
      LT -> goJust x kx vx l
      EQ -> Just (kx, vx)
      GT -> goJust x kx' x' r

-------------------------------------------------------------------
-- Insertion, deletion, update
-------------------------------------------------------------------

-- The NEW key is stored on a duplicate (containers).
insert :: Ord k => k -> a -> Map k a -> Map k a
insert kx x Tip = singleton kx x
insert kx x (Bin sz ky y l r) = case compare kx ky of
  LT -> balanceL ky y (insert kx x l) r
  GT -> balanceR ky y l (insert kx x r)
  EQ -> Bin sz kx x l r

-- Insert keeping an existing key and value (union's helper).
insertR :: Ord k => k -> a -> Map k a -> Map k a
insertR kx x Tip = singleton kx x
insertR kx x t@(Bin _ ky y l r) = case compare kx ky of
  LT -> balanceL ky y (insertR kx x l) r
  GT -> balanceR ky y l (insertR kx x r)
  EQ -> t

insertWith :: Ord k => (a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWith f = insertWithKey (\_ x' y' -> f x' y')

insertWithKey :: Ord k => (k -> a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWithKey _ kx x Tip = singleton kx x
insertWithKey f kx x (Bin sy ky y l r) = case compare kx ky of
  LT -> balanceL ky y (insertWithKey f kx x l) r
  GT -> balanceR ky y l (insertWithKey f kx x r)
  EQ -> Bin sy kx (f kx x y) l r

-- The right-biased variant keeps the OLD key: f old new.
insertWithKeyR :: Ord k => (k -> a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWithKeyR _ kx x Tip = singleton kx x
insertWithKeyR f kx x (Bin sy ky y l r) = case compare kx ky of
  LT -> balanceL ky y (insertWithKeyR f kx x l) r
  GT -> balanceR ky y l (insertWithKeyR f kx x r)
  EQ -> Bin sy ky (f ky y x) l r

insertLookupWithKey :: Ord k => (k -> a -> a -> a) -> k -> a -> Map k a
                    -> (Maybe a, Map k a)
insertLookupWithKey f kx x m = (lookup kx m, insertWithKey f kx x m)

delete :: Ord k => k -> Map k a -> Map k a
delete _ Tip = Tip
delete k (Bin _ kx x l r) = case compare k kx of
  LT -> balanceR kx x (delete k l) r
  GT -> balanceL kx x l (delete k r)
  EQ -> glue l r

adjust :: Ord k => (a -> a) -> k -> Map k a -> Map k a
adjust f = adjustWithKey (\_ x -> f x)

-- The OLD key stays (containers).
adjustWithKey :: Ord k => (k -> a -> a) -> k -> Map k a -> Map k a
adjustWithKey _ _ Tip = Tip
adjustWithKey f k (Bin sx kx x l r) = case compare k kx of
  LT -> Bin sx kx x (adjustWithKey f k l) r
  GT -> Bin sx kx x l (adjustWithKey f k r)
  EQ -> Bin sx kx (f kx x) l r

update :: Ord k => (a -> Maybe a) -> k -> Map k a -> Map k a
update f = updateWithKey (\_ x -> f x)

updateWithKey :: Ord k => (k -> a -> Maybe a) -> k -> Map k a -> Map k a
updateWithKey _ _ Tip = Tip
updateWithKey f k (Bin sx kx x l r) = case compare k kx of
  LT -> balanceR kx x (updateWithKey f k l) r
  GT -> balanceL kx x l (updateWithKey f k r)
  EQ -> case f kx x of
          Just x' -> Bin sx kx x' l r
          Nothing -> glue l r

updateLookupWithKey :: Ord k => (k -> a -> Maybe a) -> k -> Map k a
                    -> (Maybe a, Map k a)
updateLookupWithKey f k m = case lookupLE k m of
  Just (kx, x) | not (k < kx) && not (kx < k) -> case f kx x of
    Just x' -> (Just x', updateWithKey f k m)
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
          Just x' -> Bin sx kx x' l r
          Nothing -> glue l r

-------------------------------------------------------------------
-- Indexed
-------------------------------------------------------------------

findIndex :: Ord k => k -> Map k a -> Int
findIndex = go 0
  where
    go _ _ Tip = error "Map.findIndex: element is not in the map"
    go idx k (Bin _ kx _ l r) = case compare k kx of
      LT -> go idx k l
      GT -> go (idx + size l + 1) k r
      EQ -> idx + size l

lookupIndex :: Ord k => k -> Map k a -> Maybe Int
lookupIndex = go 0
  where
    go _ _ Tip = Nothing
    go idx k (Bin _ kx _ l r) = case compare k kx of
      LT -> go idx k l
      GT -> go (idx + size l + 1) k r
      EQ -> Just (idx + size l)

elemAt :: Int -> Map k a -> (k, a)
elemAt _ Tip = error "Map.elemAt: index out of range"
elemAt i (Bin _ kx x l r) = case compare i sizeL of
  LT -> elemAt i l
  GT -> elemAt (i - sizeL - 1) r
  EQ -> (kx, x)
  where sizeL = size l

deleteAt :: Int -> Map k a -> Map k a
deleteAt i t = case t of
  Tip -> error "Map.deleteAt: index out of range"
  Bin _ kx x l r -> let sizeL = size l in case compare i sizeL of
    LT -> balanceR kx x (deleteAt i l) r
    GT -> balanceL kx x l (deleteAt (i - sizeL - 1) r)
    EQ -> glue l r

take :: Int -> Map k a -> Map k a
take i0 m0
  | i0 >= size m0 = m0
  | otherwise = go i0 m0
  where
    go i m | i <= 0 = Tip
    go _ Tip = Tip
    go i (Bin _ kx x l r) = let sizeL = size l in case compare i sizeL of
      LT -> go i l
      GT -> link kx x l (go (i - sizeL - 1) r)
      EQ -> l

drop :: Int -> Map k a -> Map k a
drop i0 m0
  | i0 >= size m0 = Tip
  | otherwise = go i0 m0
  where
    go i m | i <= 0 = m
    go _ Tip = Tip
    go i (Bin _ kx x l r) = let sizeL = size l in case compare i sizeL of
      LT -> link kx x (go i l) r
      GT -> go (i - sizeL - 1) r
      EQ -> insertMin kx x r

splitAt :: Int -> Map k a -> (Map k a, Map k a)
splitAt i m = (take i m, drop i m)

-------------------------------------------------------------------
-- Minimum and maximum
-------------------------------------------------------------------

lookupMin :: Map k a -> Maybe (k, a)
lookupMin Tip = Nothing
lookupMin (Bin _ k x l _) = Just (go k x l)
  where
    go k' x' Tip = (k', x')
    go _ _ (Bin _ k' x' l' _) = go k' x' l'

lookupMax :: Map k a -> Maybe (k, a)
lookupMax Tip = Nothing
lookupMax (Bin _ k x _ r) = Just (go k x r)
  where
    go k' x' Tip = (k', x')
    go _ _ (Bin _ k' x' _ r') = go k' x' r'

findMin :: Map k a -> (k, a)
findMin t = case lookupMin t of
  Just r  -> r
  Nothing -> error "Map.findMin: empty map has no minimal element"

findMax :: Map k a -> (k, a)
findMax t = case lookupMax t of
  Just r  -> r
  Nothing -> error "Map.findMax: empty map has no maximal element"

deleteMin :: Map k a -> Map k a
deleteMin (Bin _ _ _ Tip r) = r
deleteMin (Bin _ kx x l r)  = balanceR kx x (deleteMin l) r
deleteMin Tip               = Tip

deleteMax :: Map k a -> Map k a
deleteMax (Bin _ _ _ l Tip) = l
deleteMax (Bin _ kx x l r)  = balanceL kx x l (deleteMax r)
deleteMax Tip               = Tip

minViewWithKey :: Map k a -> Maybe ((k, a), Map k a)
minViewWithKey Tip = Nothing
minViewWithKey (Bin _ k x l r) = case minViewSure k x l r of
  (km, xm, t) -> Just ((km, xm), t)

maxViewWithKey :: Map k a -> Maybe ((k, a), Map k a)
maxViewWithKey Tip = Nothing
maxViewWithKey (Bin _ k x l r) = case maxViewSure k x l r of
  (km, xm, t) -> Just ((km, xm), t)

minView :: Map k a -> Maybe (a, Map k a)
minView t = case minViewWithKey t of
  Nothing          -> Nothing
  Just ((_, x), t') -> Just (x, t')

maxView :: Map k a -> Maybe (a, Map k a)
maxView t = case maxViewWithKey t of
  Nothing          -> Nothing
  Just ((_, x), t') -> Just (x, t')

deleteFindMin :: Map k a -> ((k, a), Map k a)
deleteFindMin t = case minViewWithKey t of
  Nothing  -> (error "Map.deleteFindMin: can not return the minimal element of an empty map", Tip)
  Just res -> res

deleteFindMax :: Map k a -> ((k, a), Map k a)
deleteFindMax t = case maxViewWithKey t of
  Nothing  -> (error "Map.deleteFindMax: can not return the maximal element of an empty map", Tip)
  Just res -> res

-------------------------------------------------------------------
-- Set operations (split-based, as containers)
-------------------------------------------------------------------

unions :: Ord k => [Map k a] -> Map k a
unions = foldlStrict union empty

unionsWith :: Ord k => (a -> a -> a) -> [Map k a] -> Map k a
unionsWith f = foldlStrict (unionWith f) empty

-- Left-biased: the first map's key and value win.
union :: Ord k => Map k a -> Map k a -> Map k a
union t1 Tip = t1
union t1 (Bin _ k x Tip Tip) = insertR k x t1
union (Bin _ k x Tip Tip) t2 = insert k x t2
union Tip t2 = t2
union (Bin _ k1 x1 l1 r1) t2 = case split k1 t2 of
  (l2, r2) -> link k1 x1 (union l1 l2) (union r1 r2)

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
         Just x2 -> link k1 (f k1 x1 x2) l1l2 r1r2

difference :: Ord k => Map k a -> Map k b -> Map k a
difference Tip _ = Tip
difference t1 Tip = t1
difference t1 (Bin _ k _ l2 r2) = case split k t1 of
  (l1, r1) ->
    let l1l2 = difference l1 l2
        r1r2 = difference r1 r2
    in if size l1l2 + size r1r2 == size t1 then t1 else link2 l1l2 r1r2

(\\) :: Ord k => Map k a -> Map k b -> Map k a
m1 \\ m2 = difference m1 m2

differenceWith :: Ord k => (a -> b -> Maybe a) -> Map k a -> Map k b -> Map k a
differenceWith f t1 t2 = mergeLeft (\_ x y -> f x y) t1 t2

-- t1's keys, combined with t2's value where present.
mergeLeft :: Ord k => (k -> a -> b -> Maybe a) -> Map k a -> Map k b -> Map k a
mergeLeft f t1 t2 = mapMaybeWithKey g t1
  where g k x = case lookup k t2 of
          Nothing -> Just x
          Just y  -> f k x y

intersection :: Ord k => Map k a -> Map k b -> Map k a
intersection Tip _ = Tip
intersection _ Tip = Tip
intersection (Bin _ k x l1 r1) t2 = case splitMember k t2 of
  (l2, mb, r2) ->
    let l1l2 = intersection l1 l2
        r1r2 = intersection r1 r2
    in if mb then link k x l1l2 r1r2 else link2 l1l2 r1r2

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
         Just x2 -> link k (f k x1 x2) l1l2 r1r2
         Nothing -> link2 l1l2 r1r2

disjoint :: Ord k => Map k a -> Map k b -> Bool
disjoint Tip _ = True
disjoint _ Tip = True
disjoint (Bin 1 k _ _ _) t = k `notMember` t
disjoint (Bin _ k _ l r) t = case splitMember k t of
  (lt, found, gt) -> not found && disjoint l lt && disjoint r gt

isSubmapOf :: (Ord k, Eq a) => Map k a -> Map k a -> Bool
isSubmapOf m1 m2 = isSubmapOfBy (==) m1 m2

isSubmapOfBy :: Ord k => (a -> b -> Bool) -> Map k a -> Map k b -> Bool
isSubmapOfBy f t1 t2 = size t1 <= size t2 && all ok (toAscList t1)
  where ok (k, x) = case lookup k t2 of
          Nothing -> False
          Just y  -> f x y

restrictKeys :: Ord k => Map k a -> Set.Set k -> Map k a
restrictKeys m s = filterWithKey (\k _ -> Set.member k s) m

withoutKeys :: Ord k => Map k a -> Set.Set k -> Map k a
withoutKeys m s = filterWithKey (\k _ -> not (Set.member k s)) m

-------------------------------------------------------------------
-- Filter, partition, mapMaybe
-------------------------------------------------------------------

filter :: (a -> Bool) -> Map k a -> Map k a
filter p = filterWithKey (\_ x -> p x)

filterWithKey :: (k -> a -> Bool) -> Map k a -> Map k a
filterWithKey _ Tip = Tip
filterWithKey p (Bin _ kx x l r)
  | p kx x    = link kx x (filterWithKey p l) (filterWithKey p r)
  | otherwise = link2 (filterWithKey p l) (filterWithKey p r)

partition :: (a -> Bool) -> Map k a -> (Map k a, Map k a)
partition p = partitionWithKey (\_ x -> p x)

partitionWithKey :: (k -> a -> Bool) -> Map k a -> (Map k a, Map k a)
partitionWithKey _ Tip = (Tip, Tip)
partitionWithKey p (Bin _ kx x l r) =
  case partitionWithKey p l of
    (l1, l2) -> case partitionWithKey p r of
      (r1, r2)
        | p kx x    -> (link kx x l1 r1, link2 l2 r2)
        | otherwise -> (link2 l1 r1, link kx x l2 r2)

mapMaybe :: (a -> Maybe b) -> Map k a -> Map k b
mapMaybe f = mapMaybeWithKey (\_ x -> f x)

mapMaybeWithKey :: (k -> a -> Maybe b) -> Map k a -> Map k b
mapMaybeWithKey _ Tip = Tip
mapMaybeWithKey f (Bin _ kx x l r) = case f kx x of
  Just y  -> link kx y (mapMaybeWithKey f l) (mapMaybeWithKey f r)
  Nothing -> link2 (mapMaybeWithKey f l) (mapMaybeWithKey f r)

mapEither :: (a -> Either b c) -> Map k a -> (Map k b, Map k c)
mapEither f = mapEitherWithKey (\_ x -> f x)

mapEitherWithKey :: (k -> a -> Either b c) -> Map k a -> (Map k b, Map k c)
mapEitherWithKey _ Tip = (Tip, Tip)
mapEitherWithKey f (Bin _ kx x l r) =
  case mapEitherWithKey f l of
    (l1, l2) -> case mapEitherWithKey f r of
      (r1, r2) -> case f kx x of
        Left y  -> (link kx y l1 r1, link2 l2 r2)
        Right z -> (link2 l1 r1, link kx z l2 r2)

-------------------------------------------------------------------
-- Mapping
-------------------------------------------------------------------

map :: (a -> b) -> Map k a -> Map k b
map _ Tip = Tip
map f (Bin s k x l r) = Bin s k (f x) (map f l) (map f r)

mapWithKey :: (k -> a -> b) -> Map k a -> Map k b
mapWithKey _ Tip = Tip
mapWithKey f (Bin s k x l r) = Bin s k (f k x) (mapWithKey f l) (mapWithKey f r)

traverseWithKey :: Applicative t => (k -> a -> t b) -> Map k a -> t (Map k b)
traverseWithKey f = go
  where
    go Tip = pure Tip
    go (Bin 1 k v _ _) = fmap (\v' -> Bin 1 k v' Tip Tip) (f k v)
    go (Bin s k v l r) = pure (\l' v' r' -> Bin s k v' l' r') <*> go l <*> f k v <*> go r

mapAccum :: (a -> b -> (a, c)) -> a -> Map k b -> (a, Map k c)
mapAccum f a m = mapAccumWithKey (\a' _ x' -> f a' x') a m

mapAccumWithKey :: (a -> k -> b -> (a, c)) -> a -> Map k b -> (a, Map k c)
mapAccumWithKey _ a Tip = (a, Tip)
mapAccumWithKey f a (Bin sx kx x l r) =
  let (a1, l') = mapAccumWithKey f a l
      (a2, x') = f a1 kx x
      (a3, r') = mapAccumWithKey f a2 r
  in (a3, Bin sx kx x' l' r')

-- The greatest original key's value wins on a collision (fromList).
mapKeys :: Ord k2 => (k1 -> k2) -> Map k1 a -> Map k2 a
mapKeys f m = fromList (foldrWithKey (\k x xs -> (f k, x) : xs) [] m)

mapKeysWith :: Ord k2 => (a -> a -> a) -> (k1 -> k2) -> Map k1 a -> Map k2 a
mapKeysWith c f m = fromListWith c (foldrWithKey (\k x xs -> (f k, x) : xs) [] m)

mapKeysMonotonic :: (k1 -> k2) -> Map k1 a -> Map k2 a
mapKeysMonotonic _ Tip = Tip
mapKeysMonotonic f (Bin sx k x l r) =
  Bin sx (f k) x (mapKeysMonotonic f l) (mapKeysMonotonic f r)

-------------------------------------------------------------------
-- Folds
-------------------------------------------------------------------

foldr :: (a -> b -> b) -> b -> Map k a -> b
foldr f z0 m0 = go z0 m0
  where
    go z Tip = z
    go z (Bin _ _ x l r) = go (f x (go z r)) l

foldl :: (b -> a -> b) -> b -> Map k a -> b
foldl f z0 m0 = go z0 m0
  where
    go z Tip = z
    go z (Bin _ _ x l r) = go (f (go z l) x) r

foldrWithKey :: (k -> a -> b -> b) -> b -> Map k a -> b
foldrWithKey f z0 m0 = go z0 m0
  where
    go z Tip = z
    go z (Bin _ kx x l r) = go (f kx x (go z r)) l

foldlWithKey :: (b -> k -> a -> b) -> b -> Map k a -> b
foldlWithKey f z0 m0 = go z0 m0
  where
    go z Tip = z
    go z (Bin _ kx x l r) = go (f (go z l) kx x) r

foldr' :: (a -> b -> b) -> b -> Map k a -> b
foldr' f z0 m0 = go z0 m0
  where
    go z Tip = z
    go z (Bin _ _ x l r) = let z' = go z r in z' `seq` (let z'' = f x z' in z'' `seq` go z'' l)

foldl' :: (b -> a -> b) -> b -> Map k a -> b
foldl' f z0 m0 = go z0 m0
  where
    go z Tip = z
    go z (Bin _ _ x l r) = let z' = go z l in z' `seq` (let z'' = f z' x in z'' `seq` go z'' r)

foldrWithKey' :: (k -> a -> b -> b) -> b -> Map k a -> b
foldrWithKey' f z0 m0 = go z0 m0
  where
    go z Tip = z
    go z (Bin _ kx x l r) = let z' = go z r in z' `seq` (let z'' = f kx x z' in z'' `seq` go z'' l)

foldlWithKey' :: (b -> k -> a -> b) -> b -> Map k a -> b
foldlWithKey' f z0 m0 = go z0 m0
  where
    go z Tip = z
    go z (Bin _ kx x l r) = let z' = go z l in z' `seq` (let z'' = f z' kx x in z'' `seq` go z'' r)

foldMapWithKey :: Monoid m => (k -> a -> m) -> Map k a -> m
foldMapWithKey f = go
  where
    go Tip = mempty
    go (Bin 1 k v _ _) = f k v
    go (Bin _ k v l r) = go l `mappend` (f k v `mappend` go r)

foldlStrict :: (b -> a -> b) -> b -> [a] -> b
foldlStrict _ z [] = z
foldlStrict f z (x : xs) = let z' = f z x in z' `seq` foldlStrict f z' xs

-------------------------------------------------------------------
-- Conversion
-------------------------------------------------------------------

elems :: Map k a -> [a]
elems = foldr (:) []

keys :: Map k a -> [k]
keys = foldrWithKey (\k _ ks -> k : ks) []

assocs :: Map k a -> [(k, a)]
assocs m = toAscList m

keysSet :: Map k a -> Set.Set k
keysSet m = Set.fromDistinctAscList (keys m)

toList :: Map k a -> [(k, a)]
toList = toAscList

toAscList :: Map k a -> [(k, a)]
toAscList = foldrWithKey (\k x xs -> (k, x) : xs) []

toDescList :: Map k a -> [(k, a)]
toDescList = foldlWithKey (\xs k x -> (k, x) : xs) []

-- Later duplicates win, key and value (insert stores the new key).
fromList :: Ord k => [(k, a)] -> Map k a
fromList = foldlStrict (\t (k, x) -> insert k x t) Tip

fromListWith :: Ord k => (a -> a -> a) -> [(k, a)] -> Map k a
fromListWith f = fromListWithKey (\_ x y -> f x y)

fromListWithKey :: Ord k => (k -> a -> a -> a) -> [(k, a)] -> Map k a
fromListWithKey f = foldlStrict (\t (k, x) -> insertWithKey f k x t) Tip

-- Equal adjacent keys: the LAST key and value of the run (containers'
-- combineEq).
fromAscList :: Eq k => [(k, a)] -> Map k a
fromAscList xs = fromAscListWithKey (\_ x _ -> x) xs

fromAscListWith :: Eq k => (a -> a -> a) -> [(k, a)] -> Map k a
fromAscListWith f xs = fromAscListWithKey (\_ x y -> f x y) xs

fromAscListWithKey :: Eq k => (k -> a -> a -> a) -> [(k, a)] -> Map k a
fromAscListWithKey f xs = fromDistinctAscList (combineEqWith f xs)

combineEqWith :: Eq k => (k -> a -> a -> a) -> [(k, a)] -> [(k, a)]
combineEqWith _ [] = []
combineEqWith f (x : xs) = go x xs
  where
    go z [] = [z]
    go z@(kz, zz) (y@(ky, yy) : ys)
      | ky == kz  = go (ky, f ky yy zz) ys
      | otherwise = z : go y ys

fromDescList :: Eq k => [(k, a)] -> Map k a
fromDescList xs = fromDistinctAscList (reverse (combineEqWith (\_ x _ -> x) xs))

-- Balanced in one pass: subtree sizes differ by at most one.
fromDistinctAscList :: [(k, a)] -> Map k a
fromDistinctAscList xs = case buildB (length xs) xs of (t, _) -> t

buildB :: Int -> [(k, a)] -> (Map k a, [(k, a)])
buildB 0 ys = (Tip, ys)
buildB n ys =
  let nl = (n - 1) `div` 2 in
  case buildB nl ys of
    (l, (k, x) : ys1) -> case buildB (n - 1 - nl) ys1 of
      (r, ys2) -> (Bin n k x l r, ys2)
    (_, []) -> error "Map.fromDistinctAscList: list too short"

fromDistinctDescList :: [(k, a)] -> Map k a
fromDistinctDescList xs = fromDistinctAscList (reverse xs)

-------------------------------------------------------------------
-- Split
-------------------------------------------------------------------

split :: Ord k => k -> Map k a -> (Map k a, Map k a)
split _ Tip = (Tip, Tip)
split k (Bin _ kx x l r) = case compare k kx of
  LT -> case split k l of (lt, gt) -> (lt, link kx x gt r)
  GT -> case split k r of (lt, gt) -> (link kx x l lt, gt)
  EQ -> (l, r)

splitLookup :: Ord k => k -> Map k a -> (Map k a, Maybe a, Map k a)
splitLookup _ Tip = (Tip, Nothing, Tip)
splitLookup k (Bin _ kx x l r) = case compare k kx of
  LT -> case splitLookup k l of (lt, z, gt) -> (lt, z, link kx x gt r)
  GT -> case splitLookup k r of (lt, z, gt) -> (link kx x l lt, z, gt)
  EQ -> (l, Just x, r)

splitMember :: Ord k => k -> Map k a -> (Map k a, Bool, Map k a)
splitMember _ Tip = (Tip, False, Tip)
splitMember k (Bin _ kx x l r) = case compare k kx of
  LT -> case splitMember k l of (lt, z, gt) -> (lt, z, link kx x gt r)
  GT -> case splitMember k r of (lt, z, gt) -> (link kx x l lt, z, gt)
  EQ -> (l, True, r)

-------------------------------------------------------------------
-- Rebalancing (containers' balance / balanceL / balanceR)
-------------------------------------------------------------------

bin :: k -> a -> Map k a -> Map k a -> Map k a
bin k x l r = Bin (size l + size r + 1) k x l r

balance :: k -> a -> Map k a -> Map k a -> Map k a
balance k x l r = case l of
  Tip -> case r of
    Tip -> Bin 1 k x Tip Tip
    Bin _ _ _ Tip Tip -> Bin 2 k x Tip r
    Bin _ rk rx Tip rr@(Bin _ _ _ _ _) -> Bin 3 rk rx (Bin 1 k x Tip Tip) rr
    Bin _ rk rx (Bin _ rlk rlx _ _) Tip ->
      Bin 3 rlk rlx (Bin 1 k x Tip Tip) (Bin 1 rk rx Tip Tip)
    Bin rs rk rx rl@(Bin rls rlk rlx rll rlr) rr@(Bin rrs _ _ _ _)
      | rls < ratio * rrs -> Bin (1 + rs) rk rx (Bin (1 + rls) k x Tip rl) rr
      | otherwise -> Bin (1 + rs) rlk rlx (Bin (1 + size rll) k x Tip rll)
                                          (Bin (1 + rrs + size rlr) rk rx rlr rr)
  Bin ls lk lx ll lr -> case r of
    Tip -> case (ll, lr) of
      (Tip, Tip) -> Bin 2 k x l Tip
      (Tip, Bin _ lrk lrx _ _) ->
        Bin 3 lrk lrx (Bin 1 lk lx Tip Tip) (Bin 1 k x Tip Tip)
      (Bin _ _ _ _ _, Tip) -> Bin 3 lk lx ll (Bin 1 k x Tip Tip)
      (Bin lls _ _ _ _, Bin lrs lrk lrx lrl lrr)
        | lrs < ratio * lls -> Bin (1 + ls) lk lx ll (Bin (1 + lrs) k x lr Tip)
        | otherwise -> Bin (1 + ls) lrk lrx (Bin (1 + lls + size lrl) lk lx ll lrl)
                                            (Bin (1 + size lrr) k x lrr Tip)
    Bin rs rk rx rl rr
      | rs > delta * ls -> case (rl, rr) of
          (Bin rls rlk rlx rll rlr, Bin rrs _ _ _ _)
            | rls < ratio * rrs -> Bin (1 + ls + rs) rk rx (Bin (1 + ls + rls) k x l rl) rr
            | otherwise -> Bin (1 + ls + rs) rlk rlx (Bin (1 + ls + size rll) k x l rll)
                                                     (Bin (1 + rrs + size rlr) rk rx rlr rr)
          (_, _) -> error "Failure in Data.Map.balance"
      | ls > delta * rs -> case (ll, lr) of
          (Bin lls _ _ _ _, Bin lrs lrk lrx lrl lrr)
            | lrs < ratio * lls -> Bin (1 + ls + rs) lk lx ll (Bin (1 + rs + lrs) k x lr r)
            | otherwise -> Bin (1 + ls + rs) lrk lrx (Bin (1 + lls + size lrl) lk lx ll lrl)
                                                     (Bin (1 + rs + size lrr) k x lrr r)
          (_, _) -> error "Failure in Data.Map.balance"
      | otherwise -> Bin (1 + ls + rs) k x l r

balanceL :: k -> a -> Map k a -> Map k a -> Map k a
balanceL k x l r = case r of
  Tip -> case l of
    Tip -> Bin 1 k x Tip Tip
    Bin _ _ _ Tip Tip -> Bin 2 k x l Tip
    Bin _ lk lx Tip (Bin _ lrk lrx _ _) ->
      Bin 3 lrk lrx (Bin 1 lk lx Tip Tip) (Bin 1 k x Tip Tip)
    Bin _ lk lx ll@(Bin _ _ _ _ _) Tip -> Bin 3 lk lx ll (Bin 1 k x Tip Tip)
    Bin ls lk lx ll@(Bin lls _ _ _ _) lr@(Bin lrs lrk lrx lrl lrr)
      | lrs < ratio * lls -> Bin (1 + ls) lk lx ll (Bin (1 + lrs) k x lr Tip)
      | otherwise -> Bin (1 + ls) lrk lrx (Bin (1 + lls + size lrl) lk lx ll lrl)
                                          (Bin (1 + size lrr) k x lrr Tip)
  Bin rs _ _ _ _ -> case l of
    Tip -> Bin (1 + rs) k x Tip r
    Bin ls lk lx ll lr
      | ls > delta * rs -> case (ll, lr) of
          (Bin lls _ _ _ _, Bin lrs lrk lrx lrl lrr)
            | lrs < ratio * lls -> Bin (1 + ls + rs) lk lx ll (Bin (1 + rs + lrs) k x lr r)
            | otherwise -> Bin (1 + ls + rs) lrk lrx (Bin (1 + lls + size lrl) lk lx ll lrl)
                                                     (Bin (1 + rs + size lrr) k x lrr r)
          (_, _) -> error "Failure in Data.Map.balanceL"
      | otherwise -> Bin (1 + ls + rs) k x l r

balanceR :: k -> a -> Map k a -> Map k a -> Map k a
balanceR k x l r = case l of
  Tip -> case r of
    Tip -> Bin 1 k x Tip Tip
    Bin _ _ _ Tip Tip -> Bin 2 k x Tip r
    Bin _ rk rx Tip rr@(Bin _ _ _ _ _) -> Bin 3 rk rx (Bin 1 k x Tip Tip) rr
    Bin _ rk rx (Bin _ rlk rlx _ _) Tip ->
      Bin 3 rlk rlx (Bin 1 k x Tip Tip) (Bin 1 rk rx Tip Tip)
    Bin rs rk rx rl@(Bin rls rlk rlx rll rlr) rr@(Bin rrs _ _ _ _)
      | rls < ratio * rrs -> Bin (1 + rs) rk rx (Bin (1 + rls) k x Tip rl) rr
      | otherwise -> Bin (1 + rs) rlk rlx (Bin (1 + size rll) k x Tip rll)
                                          (Bin (1 + rrs + size rlr) rk rx rlr rr)
  Bin ls _ _ _ _ -> case r of
    Tip -> Bin (1 + ls) k x l Tip
    Bin rs rk rx rl rr
      | rs > delta * ls -> case (rl, rr) of
          (Bin rls rlk rlx rll rlr, Bin rrs _ _ _ _)
            | rls < ratio * rrs -> Bin (1 + ls + rs) rk rx (Bin (1 + ls + rls) k x l rl) rr
            | otherwise -> Bin (1 + ls + rs) rlk rlx (Bin (1 + ls + size rll) k x l rll)
                                                     (Bin (1 + rrs + size rlr) rk rx rlr rr)
          (_, _) -> error "Failure in Data.Map.balanceR"
      | otherwise -> Bin (1 + ls + rs) k x l r

insertMax :: k -> a -> Map k a -> Map k a
insertMax kx x t = case t of
  Tip -> singleton kx x
  Bin _ ky y l r -> balanceR ky y l (insertMax kx x r)

insertMin :: k -> a -> Map k a -> Map k a
insertMin kx x t = case t of
  Tip -> singleton kx x
  Bin _ ky y l r -> balanceL ky y (insertMin kx x l) r

-- Join two trees and a key between them, any sizes.
link :: k -> a -> Map k a -> Map k a -> Map k a
link kx x Tip r = insertMin kx x r
link kx x l Tip = insertMax kx x l
link kx x l@(Bin sizeL ky y ly ry) r@(Bin sizeR kz z lz rz)
  | delta * sizeL < sizeR = balanceL kz z (link kx x l lz) rz
  | delta * sizeR < sizeL = balanceR ky y ly (link kx x ry r)
  | otherwise             = bin kx x l r

-- Join two trees, any sizes, every key of l below every key of r.
link2 :: Map k a -> Map k a -> Map k a
link2 Tip r = r
link2 l Tip = l
link2 l@(Bin sizeL kx x lx rx) r@(Bin sizeR ky y ly ry)
  | delta * sizeL < sizeR = balanceL ky y (link2 l ly) ry
  | delta * sizeR < sizeL = balanceR kx x lx (link2 rx r)
  | otherwise             = glue l r

-- Join two balanced trees of compatible sizes.
glue :: Map k a -> Map k a -> Map k a
glue Tip r = r
glue l Tip = l
glue l@(Bin sl kl xl ll lr) r@(Bin sr kr xr rl rr)
  | sl > sr   = case maxViewSure kl xl ll lr of (km, m, l') -> balanceR km m l' r
  | otherwise = case minViewSure kr xr rl rr of (km, m, r') -> balanceL km m l r'

minViewSure :: k -> a -> Map k a -> Map k a -> (k, a, Map k a)
minViewSure k x Tip r = (k, x, r)
minViewSure k x (Bin _ kl xl ll lr) r = case minViewSure kl xl ll lr of
  (km, xm, l') -> (km, xm, balanceR k x l' r)

maxViewSure :: k -> a -> Map k a -> Map k a -> (k, a, Map k a)
maxViewSure k x l Tip = (k, x, l)
maxViewSure k x l (Bin _ kr xr rl rr) = case maxViewSure kr xr rl rr of
  (km, xm, r') -> (km, xm, balanceL k x l r')

-- containers' internal consistency check: ordered, balanced, sizes
-- right.
valid :: Ord k => Map k a -> Bool
valid t = balanced t && validBounded (const True) (const True) t && validsize t
  where
    balanced Tip = True
    balanced (Bin _ _ _ l r) =
      (size l + size r <= 1 || (size l <= delta * size r && size r <= delta * size l))
      && balanced l && balanced r
    validsize m = realsize m == Just (size m)
    realsize Tip = Just 0
    realsize (Bin sz _ _ l r) = case (realsize l, realsize r) of
      (Just n, Just m) | n + m + 1 == sz -> Just sz
      _ -> Nothing

validBounded :: Ord k => (k -> Bool) -> (k -> Bool) -> Map k a -> Bool
validBounded _ _ Tip = True
validBounded lo hi (Bin _ kx _ l r) =
  lo kx && hi kx && validBounded lo (< kx) l && validBounded (> kx) hi r

-------------------------------------------------------------------
-- Instances
-------------------------------------------------------------------

instance (Show k, Show a) => Show (Map k a) where
  showsPrec d m = showParen (d > 10) (showString "fromList " . shows (toList m))

instance (Eq k, Eq a) => Eq (Map k a) where
  t1 == t2 = size t1 == size t2 && toAscList t1 == toAscList t2

instance (Ord k, Ord v) => Ord (Map k v) where
  compare m1 m2 = compare (toAscList m1) (toAscList m2)

instance Functor (Map k) where
  fmap f m = map f m

-- base folds a Map over its VALUES in ascending key order, so
-- `length m` is its size and `elem v m` searches the values.
instance Foldable (Map k) where
  foldr f z m = Data.Map.Internal.foldr f z m
  foldl f z m = Data.Map.Internal.foldl f z m
  null m = Data.Map.Internal.null m
  length m = size m
  maximum m = case m of
    Tip -> error "Data.Foldable.maximum (for Data.Map): empty map"
    _   -> P.maximum (elems m)
  minimum m = case m of
    Tip -> error "Data.Foldable.minimum (for Data.Map): empty map"
    _   -> P.minimum (elems m)

instance Traversable (Map k) where
  traverse f = traverseWithKey (\_ x -> f x)

instance Ord k => Semigroup (Map k v) where
  m1 <> m2 = union m1 m2

instance Ord k => Monoid (Map k v) where
  mempty = Tip
  mconcat = unions
