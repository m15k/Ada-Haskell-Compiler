-- Data.Set (weight-balanced tree, one structure with Data.Map)
-- and the Map roundout: filter, foldlWithKey, keysSet,
-- fromDistinctAscList - all oracled against real containers.
import qualified Data.Map as Map
import qualified Data.Set as Set

s1 :: Set.Set Integer
s1 = Set.fromList [5, 1, 3, 1, 4]

m1 :: Map.Map Integer String
m1 = Map.fromList [(1, "a"), (2, "bb"), (3, "c"), (4, "dddd")]

main :: IO ()
main = do
  print s1
  print (Set.toList s1, Set.size s1, Set.null s1)
  print (Set.member 3 s1, Set.notMember 2 s1)
  print (Set.insert 2 s1)
  print (Set.delete 3 s1)
  print (Set.union s1 (Set.fromList [4, 6, 0]))
  print (Set.difference s1 (Set.fromList [1, 4]))
  print (Set.intersection s1 (Set.fromList [3, 4, 9]))
  print (Set.filter even s1)
  print (Set.map (* 10) s1)
  print (Set.fromList "banana")
  print (s1 == Set.fromList [1, 3, 4, 5], s1 == Set.delete 5 s1)
  print (Map.filter (\v -> length v == 1) m1)
  print (Map.foldlWithKey (\acc k v -> acc ++ show k ++ v) "" m1)
  print (Map.keysSet m1)
  print (Map.fromDistinctAscList [(1, 'x'), (2, 'y')])
