-- Data.Map's everyday API against containers-0.6.7 (the M142 review
-- round): key identity on Eq-equal keys, the split-based set
-- operations (each result checked with containers' own `valid`),
-- indexed and min/max access with containers' error texts, and the
-- Ord/Semigroup/Monoid/Foldable/Traversable instances.
import qualified Data.Map as M
import qualified Data.Map.Strict as S
import qualified Data.Set as Set
import Control.Exception

-- Eq and Ord ignore the tag; Show reveals it.
data K = K Int Char

instance Eq K where
  K a _ == K b _ = a == b

instance Ord K where
  compare (K a _) (K b _) = compare a b

instance Show K where
  show (K a c) = show a ++ [c]

catchErr :: String -> IO ()
catchErr s = do
  r <- try (evaluate (length s))
  case r of
    Left e  -> putStrLn ("error: " ++ takeWhile (/= '\n') (show (e :: ErrorCall)))
    Right _ -> putStrLn s

big :: M.Map Int Int
big = M.fromList [(x * 37 `mod` 101, x) | x <- [1 .. 100]]

main :: IO ()
main = do
  let km = M.fromList [(K 1 'a', "one"), (K 2 'a', "two"), (K 3 'a', "three")]
      ks = S.fromList [(K 1 'a', "one"), (K 2 'a', "two"), (K 3 'a', "three")]
  -- insert family: the NEW key
  print (M.insert (K 2 'b') "TWO" km)
  print (M.insertWith (++) (K 2 'b') "x" km, M.insertWithKey (\k a b -> show k ++ a ++ b) (K 2 'b') "x" km)
  print (S.insert (K 2 'b') "TWO" ks, S.insertWith (++) (K 2 'b') "x" ks)
  -- adjust/alter/update: the OLD key
  print (M.adjust (++ "!") (K 2 'b') km, M.adjustWithKey (\k v -> show k ++ v) (K 2 'b') km)
  print (M.alter (fmap (++ "?")) (K 2 'b') km, M.alter (const (Just "new")) (K 9 'b') km)
  print (M.update (Just . reverse) (K 3 'z') km, M.updateWithKey (\k _ -> Just (show k)) (K 3 'z') km)
  print (S.adjust (++ "!") (K 2 'b') ks, S.alter (fmap (++ "?")) (K 2 'b') ks, S.update (Just . reverse) (K 3 'z') ks)
  -- unions: the LEFT map's key
  let other = M.fromList [(K 2 'r', "deux"), (K 4 'r', "quatre")]
  print (M.union km other, M.union other km)
  print (M.unionWith (++) km other, M.unionWith (++) other km)
  print (M.unionsWith (++) [km, other, M.singleton (K 1 'z') "uno"])
  print (S.unionWith (++) km other, S.unionsWith (++) [other, km])
  print (M.intersectionWith (,) km other, M.intersectionWith (,) other km, M.intersection other km)
  print (M.fromList [(K 1 'a', 1), (K 1 'b', 2)], M.fromListWith (+) [(K 1 'a', 1), (K 1 'b', 2)])
  print (M.fromAscList [(K 1 'a', 1), (K 1 'b', 2), (K 2 'c', 3)], M.fromAscListWith (+) [(K 1 'a', 1), (K 1 'b', 2)])
  print (M.mapKeys (\(K n _) -> K (n `div` 2) 'm') km)
  -- the everyday API
  print (big M.! 37, big M.!? 37, big M.!? 0, M.size big, M.valid big)
  catchErr (show (big M.! 1000))
  print (M.foldr (:) [] km, M.foldl (flip (:)) [] km, M.foldrWithKey' (\k v a -> show k ++ v ++ a) "" km, M.foldlWithKey' (\a k v -> a ++ show k ++ v) "" km)
  print (M.unions [M.fromList [(1 :: Int, 'a')], M.fromList [(1, 'b'), (2, 'c')], M.empty])
  print (M.findMin big, M.findMax big, M.lookupMin big, M.lookupMax (M.empty :: M.Map Int Int))
  catchErr (show (M.findMin (M.empty :: M.Map Int Int)))
  catchErr (show (M.findMax (M.empty :: M.Map Int Int)))
  catchErr (show (fst (M.deleteFindMin (M.empty :: M.Map Int Int))))
  catchErr (show (fst (M.deleteFindMax (M.empty :: M.Map Int Int))))
  print (M.deleteMin km, M.deleteMax km, M.deleteMin (M.empty :: M.Map Int Int))
  print (M.valid (M.deleteMin big), M.valid (M.deleteMax big), M.deleteFindMin km)
  print (M.minView km, M.maxView km, M.minViewWithKey km, M.maxViewWithKey (M.empty :: M.Map Int Int))
  print (M.toDescList km, M.assocs km)
  let evens = M.filter even big
      odds = M.filterWithKey (\k _ -> odd k) big
  print (evens M.\\ odds == evens, M.difference big evens == M.filter odd big, M.valid (M.difference big evens))
  print (M.keys (M.intersection big evens) == M.keys evens, M.valid (M.intersectionWith (+) big odds))
  print (M.partition even (M.fromList (zip [1 .. 10 :: Int] [1 .. 10 :: Int])))
  print (M.partitionWithKey (\k _ -> k < 4) (M.fromList (zip [1 .. 6 :: Int] "abcdef")))
  print (M.mapMaybe (\v -> if v > 2 then Just (v * 10) else Nothing) (M.fromList (zip "abcd" [1 .. 4 :: Int])))
  print (M.mapMaybeWithKey (\k v -> if k /= 'b' then Just (k, v) else Nothing) (M.fromList (zip "abc" [1 .. 3 :: Int])))
  print (M.mapEither (\v -> if even v then Left v else Right (show v)) (M.fromList (zip "abcd" [1 .. 4 :: Int])))
  print (M.elemAt 0 km, M.elemAt 2 km, M.lookupIndex (K 2 'q') km, M.findIndex (K 3 'q') km)
  catchErr (show (M.elemAt 3 km))
  catchErr (show (M.elemAt (-1) km))
  catchErr (show (M.findIndex (K 7 'q') km))
  catchErr (show (M.deleteAt 9 km))
  print (M.deleteAt 1 km)
  print (M.take 2 km, M.drop 2 km, M.splitAt 1 km, M.take (-1) km, M.drop 10 km)
  print (and [M.valid (M.take n big) && M.valid (M.drop n big) | n <- [0 .. 101]])
  print (M.lookupLT (K 2 'q') km, M.lookupGT (K 2 'q') km, M.lookupLE (K 2 'q') km, M.lookupGE (K 2 'q') km)
  print (M.lookupLT (K 1 'q') km, M.lookupGT (K 3 'q') km, M.lookupLE (K 0 'q') km, M.lookupGE (K 4 'q') km)
  print (M.lookupLE (K 5 'q') km, M.lookupGE (K 0 'q') km)
  print (M.split (K 2 'q') km, M.splitLookup (K 2 'q') km, M.splitLookup (K 5 'q') km)
  print (and [let (a, b) = M.split k big in M.valid a && M.valid b && M.size a + M.size b + (if M.member k big then 1 else 0) == 100 | k <- [-1 .. 102]])
  print (M.restrictKeys big (Set.fromList [1, 2, 3, 500]), M.withoutKeys (M.fromList (zip [1 .. 5 :: Int] "abcde")) (Set.fromList [2, 4]))
  print (M.valid (M.restrictKeys big (Set.fromList [0, 2 .. 100])), M.notMember 3 big)
  print (M.mapKeys (`div` 3) (M.fromList (zip [1 .. 9 :: Int] "abcdefghi")))
  print (M.mapKeysWith (++) (`div` 3) (M.fromList (zip [1 .. 9 :: Int] (map (: []) "abcdefghi"))))
  print (S.mapKeysWith (++) (`div` 3) (S.fromList (zip [1 .. 9 :: Int] (map (: []) "abcdefghi"))))
  print (M.fromAscList [(1 :: Int, 'a'), (1, 'b'), (2, 'c')], M.fromAscListWith (++) [(1 :: Int, "a"), (1, "b"), (2, "c")])
  print (M.fromDescList [(5 :: Int, 'a'), (5, 'b'), (3, 'c')], M.fromDistinctAscList [(1 :: Int, 'x'), (2, 'y')])
  print (M.toAscList km, M.isSubmapOf (M.take 2 big) big, M.isSubmapOf big (M.take 2 big), M.disjoint evens odds)
  print (M.mapAccum (\a v -> (a + v, a)) 0 (M.fromList (zip "abc" [1 .. 3 :: Int])))
  print (M.mapAccumWithKey (\a k v -> (a ++ [k], v * 2)) "" (M.fromList (zip "abc" [1 .. 3 :: Int])))
  print (M.foldMapWithKey (\k v -> [(k, v)]) (M.fromList (zip "ab" [1, 2 :: Int])))
  print (M.insertLookupWithKey (\_ a b -> a + b) 'a' 10 (M.fromList (zip "ab" [1, 2 :: Int])))
  print (M.updateLookupWithKey (\_ _ -> Nothing) 'a' (M.fromList (zip "ab" [1, 2 :: Int])))
  print (M.updateLookupWithKey (\_ v -> Just (v * 7)) 'b' (M.fromList (zip "ab" [1, 2 :: Int])))
  print (M.differenceWith (\a b -> if b then Just (a * 100) else Nothing) (M.fromList (zip "abc" [1 .. 3 :: Int])) (M.fromList (zip "bc" [True, False])))
  -- instances
  print (compare km (M.insert (K 4 'a') "four" km), compare (M.fromList [(1 :: Int, 'b')]) (M.fromList [(1, 'a'), (2, 'a')]))
  print (km < M.delete (K 1 'a') km, max (M.fromList [(1 :: Int, 'a')]) (M.fromList [(0, 'z')]))
  print (km <> other, other <> km, mempty :: M.Map Int Int, mconcat [other, km])
  print (sum big, product (M.fromList (zip "abc" [2, 3, 4 :: Int])), maximum big, minimum big, length big, elem 100 big, null km)
  catchErr (show (maximum (M.empty :: M.Map Int Int)))
  catchErr (show (minimum (M.empty :: M.Map Int Int)))
  print (traverse (\v -> if v > 0 then Just (v * 2) else Nothing) (M.fromList (zip "abc" [1 .. 3 :: Int])))
  print (traverse (\v -> if v > 1 then Just v else Nothing) (M.fromList (zip "abc" [1 .. 3 :: Int])))
  print (M.traverseWithKey (\k v -> [(k, v), (k, v + 1)]) (M.fromList (zip "ab" [1, 10 :: Int])))
  print (fmap length km, M.map length km, S.map length ks, S.mapWithKey (\k v -> show k ++ v) ks)
  -- strictness: Data.Map.Strict forces stored values, Data.Map does not
  r1 <- try (evaluate (S.fromDistinctAscList [(1 :: Int, 'a'), (2, undefined)]))
  putStrLn (either (\e -> "strict fromDistinctAscList: " ++ takeWhile (/= '\n') (show (e :: ErrorCall))) (const "lazy?!") r1)
  print (M.size (M.fromDistinctAscList [(1 :: Int, 'a'), (2, undefined)]))
  r2 <- try (evaluate (S.fromAscList [(1 :: Int, 'a'), (2, undefined)]))
  putStrLn (either (\e -> "strict fromAscList: " ++ takeWhile (/= '\n') (show (e :: ErrorCall))) (const "lazy?!") r2)
  r3 <- try (evaluate (S.unionWith (\_ _ -> undefined) (M.fromList [(1 :: Int, 'a')]) (M.fromList [(1, 'b')])))
  putStrLn (either (\e -> "strict unionWith: " ++ takeWhile (/= '\n') (show (e :: ErrorCall))) (const "lazy?!") r3)
  r4 <- try (evaluate (S.mapMaybe (\_ -> Just undefined) (M.fromList [(1 :: Int, 'a')]) :: M.Map Int Char))
  putStrLn (either (\e -> "strict mapMaybe: " ++ takeWhile (/= '\n') (show (e :: ErrorCall))) (const "lazy?!") r4)
  r5 <- try (evaluate (S.intersectionWith (\_ _ -> undefined) (M.fromList [(1 :: Int, 'a')]) (M.fromList [(1, 'b')]) :: M.Map Int Char))
  putStrLn (either (\e -> "strict intersectionWith: " ++ takeWhile (/= '\n') (show (e :: ErrorCall))) (const "lazy?!") r5)
  print (M.size (M.intersectionWith (\_ _ -> undefined :: Char) (M.fromList [(1 :: Int, 'a')]) (M.fromList [(1, 'b')])))
  print (M.size (M.mapMaybe (\_ -> Just (undefined :: Char)) (M.fromList [(1 :: Int, 'a')])))
  -- a bottom deep in the tree: Strict.map/mapWithKey force every value
  r6 <- try (evaluate (S.map (\x -> if x == 50 then undefined else x) (S.fromList [(i, i) | i <- [1 .. 100 :: Int]])))
  putStrLn (either (\e -> "strict map: " ++ takeWhile (/= '\n') (show (e :: ErrorCall))) (const "lazy?!") r6)
  r7 <- try (evaluate (S.mapWithKey (\k x -> if k == 77 then undefined else x) (S.fromList [(i, i) | i <- [1 .. 100 :: Int]])))
  putStrLn (either (\e -> "strict mapWithKey: " ++ takeWhile (/= '\n') (show (e :: ErrorCall))) (const "lazy?!") r7)
  print (M.size (M.map (\x -> if x == 50 then undefined else x) big), S.findWithDefault (undefined :: Int) 1 (S.singleton (1 :: Int) 1))
