k :: Maybe Int -> Int -> Int
k m n = case m of { Just f -> case n of 0 -> f; _ -> 1 }
main :: IO ()
main = print (k (Just 4) 0, k (Just 4) 3)
