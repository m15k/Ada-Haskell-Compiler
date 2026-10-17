data W = W Int deriving (Show, Eq)
instance Ord W where
  compare _ _ = GT
  _ < _ = True
  _ <= _ = False
  _ > _ = False
  _ >= _ = True
  max a _ = a
  min _ b = b

data Le = Le Int deriving (Show, Eq)
instance Ord Le where Le a <= Le b = a >= b

data H = H Int deriving Show
instance Eq H where
  _ == _ = False
  _ /= _ = False

data P a = P Int a deriving (Show, Eq, Ord)
data Q = Q W deriving (Show, Eq, Ord)
data S = S1 W | S2 W W deriving (Show, Eq, Ord)

main = do
  print (Q (W 1) < Q (W 1), Q (W 1) <= Q (W 1), Q (W 1) > Q (W 1), Q (W 1) >= Q (W 1), compare (Q (W 1)) (Q (W 1)))
  print (P 1 (W 1) < P 1 (W 1), P 1 (W 1) > P 1 (W 1), max (P 1 (W 1)) (P 1 (W 2)))
  print (Just (W 1) < Just (W 1), Just (W 1) > Just (W 1), max (Just (W 1)) (Just (W 2)))
  print ([W 1] < [W 1], (W 1, W 2) < (W 1, W 2), (1::Int, W 2) < (1, W 2))
  print (S2 (W 1) (W 2) < S2 (W 1) (W 2), S1 (W 1) <= S1 (W 1))
  print (Left (W 1) < (Left (W 2) :: Either W W))
  print (P 0 (Le 1) < P 0 (Le 2), compare (P 0 (Le 1)) (P 0 (Le 2)), compare [Le 1] [Le 2], Just (Le 3) > Just (Le 1))
  print (max (P 0 (Le 1)) (P 0 (Le 2)), min [Le 1] [Le 2])
  print (P 1 (H 1) == P 1 (H 1), P 1 (H 1) /= P 1 (H 1), Just (H 1) /= Just (H 1), [H 1] /= [H 1], (H 1, 'a') /= (H 1, 'a'))
