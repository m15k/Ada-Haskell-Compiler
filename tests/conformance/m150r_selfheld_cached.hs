data W = W Int deriving Show
instance Eq W where
  (==) = eqs `seq` (\(W a) (W b) -> a `mod` 10 == b `mod` 10)
    where eqs = ((==) :: [W] -> [W] -> Bool)
instance Ord W where
  compare (W a) (W b) = compare (a `mod` 10) (b `mod` 10)
main :: IO ()
main = do
  print (W 1 == W 11)
  print (lookup [W 11] [([W 1], "found")])
  print (elem [W 21] [[W 1]], [W 3, W 4] == [W 13, W 14])
