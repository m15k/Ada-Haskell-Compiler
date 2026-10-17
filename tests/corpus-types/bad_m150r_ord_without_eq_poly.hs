data X = X Int deriving Ord
g :: Ord a => a -> a -> Bool
g x y = x == y
main = print (X 1 < X 2, g (X 1) (X 1))
