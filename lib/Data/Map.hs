module Data.Map
  ( Map, empty, singleton, null, size, member, notMember
  , lookup, findWithDefault, insert, insertWith, delete, adjust
  , union, unionWith, fromList, toList, toAscList, keys, elems
  , map, foldrWithKey
  ) where

--  A weight-balanced binary search tree (Adams' algorithm, the same
--  family as GHC's containers library). Keys are kept in strict
--  ascending order, so everything observable - toList order, Show
--  format, Eq - matches containers exactly; conformance tests
--  oracle against the real thing. null/lookup/map deliberately
--  shadow the Prelude (import qualified, as with containers).

data Map k a
  = Bin Int k a (Map k a) (Map k a)
  | Tip

delta :: Int
delta = 3

ratio :: Int
ratio = 2

empty :: Map k a
empty = Tip

singleton :: k -> a -> Map k a
singleton k x = Bin 1 k x Tip Tip

null :: Map k a -> Bool
null Tip = True
null _ = False

size :: Map k a -> Int
size Tip = 0
size (Bin s _ _ _ _) = s

lookup :: Ord k => k -> Map k a -> Maybe a
lookup _ Tip = Nothing
lookup k (Bin _ kx x l r) =
  case compare k kx of
    LT -> lookup k l
    GT -> lookup k r
    EQ -> Just x

member :: Ord k => k -> Map k a -> Bool
member k m =
  case lookup k m of
    Just _ -> True
    Nothing -> False

notMember :: Ord k => k -> Map k a -> Bool
notMember k m = not (member k m)

findWithDefault :: Ord k => a -> k -> Map k a -> a
findWithDefault d k m =
  case lookup k m of
    Just x -> x
    Nothing -> d

--  Smart constructor: sizes below are already consistent.
bin :: k -> a -> Map k a -> Map k a -> Map k a
bin k x l r = Bin (size l + size r + 1) k x l r

--  Rebalance after one insertion or deletion on either side.
balance :: k -> a -> Map k a -> Map k a -> Map k a
balance k x l r
  | size l + size r <= 1 = bin k x l r
  | size r > delta * size l = rotateL k x l r
  | size l > delta * size r = rotateR k x l r
  | otherwise = bin k x l r

rotateL :: k -> a -> Map k a -> Map k a -> Map k a
rotateL k x l r =
  case r of
    Bin _ _ _ rl rr ->
      if size rl < ratio * size rr
        then singleL k x l r
        else doubleL k x l r
    Tip -> bin k x l r

rotateR :: k -> a -> Map k a -> Map k a -> Map k a
rotateR k x l r =
  case l of
    Bin _ _ _ ll lr ->
      if size lr < ratio * size ll
        then singleR k x l r
        else doubleR k x l r
    Tip -> bin k x l r

singleL :: k -> a -> Map k a -> Map k a -> Map k a
singleL k x l (Bin _ rk rx rl rr) = bin rk rx (bin k x l rl) rr
singleL k x l Tip = bin k x l Tip

singleR :: k -> a -> Map k a -> Map k a -> Map k a
singleR k x (Bin _ lk lx ll lr) r = bin lk lx ll (bin k x lr r)
singleR k x Tip r = bin k x Tip r

doubleL :: k -> a -> Map k a -> Map k a -> Map k a
doubleL k x l (Bin _ rk rx (Bin _ rlk rlx rll rlr) rr) =
  bin rlk rlx (bin k x l rll) (bin rk rx rlr rr)
doubleL k x l r = bin k x l r

doubleR :: k -> a -> Map k a -> Map k a -> Map k a
doubleR k x (Bin _ lk lx ll (Bin _ lrk lrx lrl lrr)) r =
  bin lrk lrx (bin lk lx ll lrl) (bin k x lrr r)
doubleR k x l r = bin k x l r

--  insert: replaces the value on a duplicate key (containers
--  semantics). The structure is not rebuilt on replacement.
insert :: Ord k => k -> a -> Map k a -> Map k a
insert k x Tip = singleton k x
insert k x (Bin s kx y l r) =
  case compare k kx of
    LT -> balance kx y (insert k x l) r
    GT -> balance kx y l (insert k x r)
    EQ -> Bin s k x l r

--  insertWith f k new: on a duplicate key stores f new old.
insertWith :: Ord k => (a -> a -> a) -> k -> a -> Map k a -> Map k a
insertWith _ k x Tip = singleton k x
insertWith f k x (Bin s kx y l r) =
  case compare k kx of
    LT -> balance kx y (insertWith f k x l) r
    GT -> balance kx y l (insertWith f k x r)
    EQ -> Bin s kx (f x y) l r

delete :: Ord k => k -> Map k a -> Map k a
delete _ Tip = Tip
delete k (Bin _ kx x l r) =
  case compare k kx of
    LT -> balance kx x (delete k l) r
    GT -> balance kx x l (delete k r)
    EQ -> glue l r

--  Join two trees whose keys are already ordered around a deleted
--  root: pull up the minimum of the right side.
glue :: Map k a -> Map k a -> Map k a
glue Tip r = r
glue l Tip = l
glue l r =
  case deleteFindMin r of
    ((km, xm), r') -> balance km xm l r'

deleteFindMin :: Map k a -> ((k, a), Map k a)
deleteFindMin (Bin _ k x Tip r) = ((k, x), r)
deleteFindMin (Bin _ k x l r) =
  case deleteFindMin l of
    ((km, xm), l') -> ((km, xm), balance k x l' r)
deleteFindMin Tip =
  error "Map.deleteFindMin: empty map"

adjust :: Ord k => (a -> a) -> k -> Map k a -> Map k a
adjust _ _ Tip = Tip
adjust f k (Bin s kx x l r) =
  case compare k kx of
    LT -> Bin s kx x (adjust f k l) r
    GT -> Bin s kx x l (adjust f k r)
    EQ -> Bin s kx (f x) l r

--  Left-biased union, like containers: on duplicate keys the FIRST
--  map's value wins.
union :: Ord k => Map k a -> Map k a -> Map k a
union m1 m2 = goU m1 (toList m2)
  where
    goU m [] = m
    goU m ((k, x) : rest) =
      if member k m then goU m rest else goU (insert k x m) rest

--  unionWith f: on duplicate keys stores f leftValue rightValue.
unionWith :: Ord k => (a -> a -> a) -> Map k a -> Map k a -> Map k a
unionWith f m1 m2 = goW m1 (toList m2)
  where
    goW m [] = m
    goW m ((k, x) : rest) =
      case lookup k m of
        Just y -> goW (insert k (f y x) m) rest
        Nothing -> goW (insert k x m) rest

--  fromList: later duplicates win (containers semantics).
fromList :: Ord k => [(k, a)] -> Map k a
fromList ps = goF empty ps
  where
    goF m [] = m
    goF m ((k, x) : rest) = goF (insert k x m) rest

toList :: Map k a -> [(k, a)]
toList m = toAscList m

toAscList :: Map k a -> [(k, a)]
toAscList m = go m []
  where
    go Tip acc = acc
    go (Bin _ k x l r) acc = go l ((k, x) : go r acc)

keys :: Map k a -> [k]
keys m = goK (toAscList m)
  where
    goK [] = []
    goK ((k, _) : rest) = k : goK rest

elems :: Map k a -> [a]
elems m = goE (toAscList m)
  where
    goE [] = []
    goE ((_, x) : rest) = x : goE rest

map :: (a -> b) -> Map k a -> Map k b
map _ Tip = Tip
map f (Bin s k x l r) = Bin s k (f x) (map f l) (map f r)

--  Right fold over key/value pairs in ascending key order.
foldrWithKey :: (k -> a -> b -> b) -> b -> Map k a -> b
foldrWithKey _ z Tip = z
foldrWithKey f z (Bin _ k x l r) =
  foldrWithKey f (f k x (foldrWithKey f z r)) l

instance (Show k, Show a) => Show (Map k a) where
  showsPrec d m s =
    showParen (d > 10)
      (\t -> "fromList " ++ shows (toList m) t) s

instance (Eq k, Eq a) => Eq (Map k a) where
  m1 == m2 = toList m1 == toList m2
