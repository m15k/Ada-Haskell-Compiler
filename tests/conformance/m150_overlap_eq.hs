{-# LANGUAGE FlexibleInstances #-}
-- M150 D1: an OVERLAPPING Eq [Bool] is used inside derived and wired
-- instances, not bypassed by the structural primitive.

instance {-# OVERLAPPING #-} Eq [Bool] where
  xs == ys = length xs == length ys

data Flags = Flags [Bool] Int deriving (Eq, Show)

main :: IO ()
main = do
  print ([True] == [False], [True, True] == [False])
  print (Flags [True] 1 == Flags [False] 1, Flags [True] 1 == Flags [] 1)
  print (Just [True, False] == Just [False, True])
  print ([[True]] == [[False]], ([True], 'x') == ([False], 'x'))
  print ([1, 2 :: Int] == [1, 2], "ab" == "ab")
