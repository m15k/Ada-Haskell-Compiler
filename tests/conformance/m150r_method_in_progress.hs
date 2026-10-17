data H = H Int deriving Show
instance Eq H where
  (==) = let eqL = ((==) :: [H] -> [H] -> Bool) in eqL `seq` (\(H a) (H b) -> a `mod` 10 == b `mod` 10)
data Box = Box [H] deriving (Eq, Show)
main = do
  print (H 1 == H 11)
  print ([H 1] == [H 11], Just [H 2] == Just [H 12], Box [H 3] == Box [H 13])
