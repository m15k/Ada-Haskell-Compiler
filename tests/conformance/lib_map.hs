-- Data.Map: AHC's lib/Data/Map.hs vs GHC's real containers library.
-- Everything observable must agree: toList order, Show format,
-- union bias, duplicate-key semantics.
import qualified Data.Map as Map

type IM = Map.Map Integer String

m1 :: IM
m1 = Map.fromList [(3, "c"), (1, "a"), (2, "b"), (1, "A")]

big :: Map.Map Integer Integer
big = Map.fromList [(x * 7 - (x * 7 `div` 20) * 20, x) | x <- [1 .. 40]]

main :: IO ()
main = do
  print m1
  print (Map.toList m1)
  print (Map.size m1, Map.null m1, Map.null (Map.empty :: IM))
  print (Map.lookup 2 m1, Map.lookup 9 m1)
  print (Map.member 3 m1, Map.notMember 3 m1)
  print (Map.findWithDefault "?" 9 m1)
  print (Map.insert 2 "B" m1)
  print (Map.insertWith (++) 2 "x" m1)
  print (Map.insertWith (++) 9 "x" m1)
  print (Map.delete 2 m1, Map.delete 9 m1)
  print (Map.adjust (++ "!") 1 m1)
  print (Map.union m1 (Map.fromList [(2, "two"), (4, "four")]))
  print (Map.unionWith (++) m1 (Map.fromList [(2, "two"), (4, "four")]))
  print (Map.keys m1, Map.elems m1)
  print (Map.map (++ "*") m1)
  print (Map.foldrWithKey (\k v acc -> show k ++ v ++ acc) "" m1)
  print (m1 == Map.fromList [(1, "A"), (2, "b"), (3, "c")], m1 == Map.delete 3 m1)
  print (Just m1)
  print (Map.size big, Map.keys big)
  print (Map.toList (foldr Map.delete big [0, 2 .. 18]))
  print (Map.singleton "k" (True, 1 :: Integer))
