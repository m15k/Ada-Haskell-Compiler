{-# LANGUAGE FlexibleInstances #-}
data X = X Int deriving Ord
data Y a = Y a deriving Ord
instance Eq (Y Int) where _ == _ = True
main = print (X 1 < X 2, Y 'a' < Y 'b')
