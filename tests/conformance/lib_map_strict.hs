-- Data.Map.Strict and the rest of Data.Map's everyday API (M142):
-- the strict map forces each stored value, the lazy one does not.
import qualified Data.Map as L
import qualified Data.Map.Strict as M
import Control.Exception

main :: IO ()
main = do
  let m = M.fromListWith (++) [(1 :: Int, "a"), (2, "b"), (1, "c")]
  print m
  print (M.toList (M.alter (fmap (++ "!")) 2 m), M.update (const Nothing) 1 m)
  print (M.alter (const (Just "new")) 9 m, L.alter (const Nothing) 1 m)
  print (M.unionWith (++) m (M.fromList [(1, "z"), (3, "y")]))
  print (M.foldr' (\v n -> length v + n) 0 m, M.foldl' (\n v -> n + length v) 0 m)
  print (M.mapWithKey (\k v -> show k ++ v) m, fmap length m)
  print (L.size (L.insert 9 undefined m))
  r <- try (evaluate (M.insert 9 undefined m))
  putStrLn (either (\e -> "strict: " ++ takeWhile (/= '\n') (show (e :: ErrorCall))) (const "lazy?!") r)
  r2 <- try (evaluate (M.adjust (const undefined) 1 m))
  putStrLn (either (\e -> "strict adjust: " ++ takeWhile (/= '\n') (show (e :: ErrorCall))) (const "lazy?!") r2)
  print (M.insertWithKey (\k a b -> show k ++ a ++ b) 1 "N" m)
  print (L.unionsWith (+) [L.fromList [(1 :: Int, 1 :: Int)], L.fromList [(1, 2), (2, 3)]])
  print (L.fromListWithKey (\k a b -> show k ++ a ++ b) [(1 :: Int, "x"), (1, "y"), (2, "z")])
  print (L.adjustWithKey (\k v -> v ++ show k) 2 m)
