{-# LANGUAGE GeneralizedNewtypeDeriving #-}
-- GND with contexts (Wrap a needs Num a), a tuple representation and a
-- newtype over a newtype (M147), oracled against GHC 9.4.8.
newtype Age = Age Int deriving (Show, Eq, Ord, Num)
newtype Counter a = Counter (Maybe a) deriving (Functor, Show)
newtype Wrap a = Wrap a deriving (Show, Eq, Num)
newtype Pair a = Pair (a, Int) deriving (Show, Eq, Ord)
newtype Nest = Nest Age deriving (Show, Eq, Num)
main :: IO ()
main = do
  print (Age 3 + Age 4)
  print (fmap (+1) (Counter (Just (1::Int))))
  print (Wrap (2 :: Int) * 5, Wrap 'x' == Wrap 'x', Pair (1 :: Int, 2) < Pair (1, 3))
  print (Nest 2 + 3)
