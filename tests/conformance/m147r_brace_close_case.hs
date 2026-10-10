{-# LANGUAGE LambdaCase #-}
k :: Maybe Int -> Int -> Int
k = \case { Just f -> \case 0 -> f; _ -> 1 }
main :: IO ()
main = print (k (Just 4) 0, k (Just 4) 3)
