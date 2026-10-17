data W a = W a deriving (Show, Ord)
instance (Show a, Eq a) => Eq (W a) where W x == W y = show x == show y
g :: Ord a => a -> a -> Bool
g x y = x == y
data N a = N (N [a]) | L a deriving (Show, Eq, Ord)
data Ev a = EZ | ES a (Od a) deriving (Show, Eq, Ord)
data Od a = OS a (Ev a) deriving (Show, Eq, Ord)
data H = H Int deriving Show
instance Eq H where _ == _ = True
instance Ord H where compare _ _ = EQ
main = do
  print (N (N (L [[1]])) == N (N (L [[1::Int]])), N (L [H 1]) == N (L [H 2]), compare (N (L [H 1])) (L (H 2)))
  print (N (N (L [[H 1]])) == N (N (L [[H 2]])), compare (N (N (L [[H 1, H 3]]))) (N (N (L [[H 2]]))))
  print (ES (H 1) (OS (H 2) EZ) == ES (H 3) (OS (H 4) EZ), ES 1 (OS 2 EZ) < ES 1 (OS 3 EZ))
  print (compare (ES (H 1) (OS (H 2) EZ)) (ES (H 3) (OS (H 4) (ES (H 1) (OS (H 1) EZ)))))
