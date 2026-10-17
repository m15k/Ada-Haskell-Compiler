{-# LANGUAGE FlexibleInstances #-}
data B = B Bool deriving Show
instance {-# OVERLAPPING #-} Eq [B] where _ == _ = True
instance Eq B where B x == B y = x == y
instance {-# OVERLAPPING #-} Eq (Maybe Int) where _ == _ = True
data R = R [B] (Maybe Int) deriving (Eq, Show)
data S a = S [a] (Maybe a) deriving (Eq, Show)
main = do
  print ([B True] == [B False], Just (1::Int) == Just 2)
  print (R [B True] (Just 1) == R [B False] (Just 2))
  print (S [B True] Nothing == S [B False] Nothing, S [1::Int] (Just 1) == S [1] (Just 2))
  print (Just [B True] == Just [B False], ([B True], 'a') == ([B False], 'a'))
