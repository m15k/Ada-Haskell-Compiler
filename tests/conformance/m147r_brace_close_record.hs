{-# LANGUAGE LambdaCase #-}
f :: Int -> String
f x | any (\case 0 -> True; _ -> False) [x] = "z"
    | otherwise = "nz"
g :: Int -> Int
g = id $ \case 0 -> 1; n -> n :: Int
data R = R { fld :: Int -> Int }
r :: R
r = R { fld = (\case 0 -> 7; n -> n) }
r2 :: R
r2 = r { fld = (\case 1 -> 8; n -> n) }
main :: IO ()
main = do
  putStrLn (f 0 ++ f 1)
  print (g 0, g 5, fld r 0, fld r2 1, fld r2 3)
