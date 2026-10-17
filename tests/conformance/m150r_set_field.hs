import qualified Data.Set as S
data A = A (S.Set Int) deriving (Eq, Ord, Show)
main = do
  let x = A (S.fromList [1..7]); y = A (S.fromList (reverse [1..7] ++ [8]))
  print (x == A (S.fromList (reverse [1..7])), compare x y, compare (A (S.fromList [2])) (A (S.fromList [1,3])))
