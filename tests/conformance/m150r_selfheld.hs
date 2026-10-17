data W = W Int deriving Show

instance Eq W where
  (==) = eqs `seq` (\(W a) (W b) -> a `mod` 10 == b `mod` 10)
    where eqs = ((==) :: [W] -> [W] -> Bool)

main :: IO ()
main = do
  print (W 1 == W 11)
  print ([W 1] == [W 11])
  print (Just (W 1) == Just (W 11))
