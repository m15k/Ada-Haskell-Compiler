module Data.Set
  ( Set, empty, singleton, null, size, member, notMember
  , insert, delete, union, difference, intersection
  , fromList, fromDistinctAscList, toList, toAscList, elems
  , filter, map
  ) where

--  Constructor names are SBin/STip (not exported) because the
--  renamer's constructor namespace is flat across modules and
--  Data.Map owns Bin/Tip; per-module namespaces are the M75 item.
--  A weight-balanced binary search tree (Adams' algorithm), the
--  Data.Map structure without values; observable behavior matches
--  containers (toList order, "fromList [...]" Show, left-biased
--  union). null/filter/map shadow the Prelude - import qualified.

data Set a
  = SBin Int a (Set a) (Set a)
  | STip

delta :: Int
delta = 3

ratio :: Int
ratio = 2

empty :: Set a
empty = STip

singleton :: a -> Set a
singleton x = SBin 1 x STip STip

null :: Set a -> Bool
null STip = True
null _ = False

size :: Set a -> Int
size STip = 0
size (SBin s _ _ _) = s

member :: Ord a => a -> Set a -> Bool
member _ STip = False
member x (SBin _ y l r) =
  case compare x y of
    LT -> member x l
    GT -> member x r
    EQ -> True

notMember :: Ord a => a -> Set a -> Bool
notMember x s = not (member x s)

bin :: a -> Set a -> Set a -> Set a
bin x l r = SBin (size l + size r + 1) x l r

balance :: a -> Set a -> Set a -> Set a
balance x l r
  | size l + size r <= 1 = bin x l r
  | size r > delta * size l = rotateL x l r
  | size l > delta * size r = rotateR x l r
  | otherwise = bin x l r

rotateL :: a -> Set a -> Set a -> Set a
rotateL x l r =
  case r of
    SBin _ _ rl rr ->
      if size rl < ratio * size rr
        then singleL x l r
        else doubleL x l r
    STip -> bin x l r

rotateR :: a -> Set a -> Set a -> Set a
rotateR x l r =
  case l of
    SBin _ _ ll lr ->
      if size lr < ratio * size ll
        then singleR x l r
        else doubleR x l r
    STip -> bin x l r

singleL :: a -> Set a -> Set a -> Set a
singleL x l (SBin _ ry rl rr) = bin ry (bin x l rl) rr
singleL x l STip = bin x l STip

singleR :: a -> Set a -> Set a -> Set a
singleR x (SBin _ ly ll lr) r = bin ly ll (bin x lr r)
singleR x STip r = bin x STip r

doubleL :: a -> Set a -> Set a -> Set a
doubleL x l (SBin _ ry (SBin _ rly rll rlr) rr) =
  bin rly (bin x l rll) (bin ry rlr rr)
doubleL x l r = bin x l r

doubleR :: a -> Set a -> Set a -> Set a
doubleR x (SBin _ ly ll (SBin _ lry lrl lrr)) r =
  bin lry (bin ly ll lrl) (bin x lrr r)
doubleR x l r = bin x l r

insert :: Ord a => a -> Set a -> Set a
insert x STip = singleton x
insert x t =
  case t of
    SBin s y l r ->
      case compare x y of
        LT -> balance y (insert x l) r
        GT -> balance y l (insert x r)
        EQ -> SBin s x l r

delete :: Ord a => a -> Set a -> Set a
delete _ STip = STip
delete x (SBin _ y l r) =
  case compare x y of
    LT -> balance y (delete x l) r
    GT -> balance y l (delete x r)
    EQ -> glue l r

glue :: Set a -> Set a -> Set a
glue STip r = r
glue l STip = l
glue l r =
  case deleteFindMin r of
    (m, r') -> balance m l r'

deleteFindMin :: Set a -> (a, Set a)
deleteFindMin (SBin _ x STip r) = (x, r)
deleteFindMin (SBin _ x l r) =
  case deleteFindMin l of
    (m, l') -> (m, balance x l' r)
deleteFindMin STip = error "Set.deleteFindMin: empty set"

--  Left-biased union, like containers.
union :: Ord a => Set a -> Set a -> Set a
union s1 s2 = goU s1 (toList s2)
  where
    goU s [] = s
    goU s (x : rest) =
      if member x s then goU s rest else goU (insert x s) rest

difference :: Ord a => Set a -> Set a -> Set a
difference s1 s2 = goD s1 (toList s2)
  where
    goD s [] = s
    goD s (x : rest) = goD (delete x s) rest

intersection :: Ord a => Set a -> Set a -> Set a
intersection s1 s2 =
  fromDistinctAscList
    (goI (toList s1))
  where
    goI [] = []
    goI (x : rest) =
      if member x s2 then x : goI rest else goI rest

fromList :: Ord a => [a] -> Set a
fromList xs = goF empty xs
  where
    goF s [] = s
    goF s (x : rest) = goF (insert x s) rest

--  Build balanced from a strictly ascending list (no comparisons).
fromDistinctAscList :: [a] -> Set a
fromDistinctAscList xs = goB (length xs) xs
  where
    goB 0 _ = STip
    goB n ys =
      case splitAt (div n 2) ys of
        (ls, m : rs) ->
          SBin n m (goB (div n 2) ls)
                  (goB (n - div n 2 - 1) rs)
        (_, []) -> STip

toList :: Set a -> [a]
toList s = toAscList s

toAscList :: Set a -> [a]
toAscList s = go s []
  where
    go STip acc = acc
    go (SBin _ x l r) acc = go l (x : go r acc)

elems :: Set a -> [a]
elems s = toAscList s

filter :: (a -> Bool) -> Set a -> Set a
filter p s = fromDistinctAscList (goFil (toAscList s))
  where
    goFil [] = []
    goFil (x : rest) =
      if p x then x : goFil rest else goFil rest

map :: Ord b => (a -> b) -> Set a -> Set b
map f s = fromList (goM (toAscList s))
  where
    goM [] = []
    goM (x : rest) = f x : goM rest

instance Show a => Show (Set a) where
  showsPrec d s0 s =
    showParen (d > 10)
      (\t -> "fromList " ++ shows (toList s0) t) s

instance Eq a => Eq (Set a) where
  a == b = toList a == toList b
