import Re
main :: IO ()
main = print (fromMaybe 0 (Just (3 :: Int)))
