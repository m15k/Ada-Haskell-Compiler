{-# LANGUAGE LambdaCase #-}
-- \cases (GHC 9.4's LambdaCase), always on in AHC (M148).
combine :: Maybe Int -> Int -> Int
combine = \cases
  (Just x) y | y > 0 -> x + y
             | otherwise -> x
  Nothing _ -> 0

zip3' :: [a] -> [b] -> [c] -> [(a, b, c)]
zip3' = \cases
  (a:as) (b:bs) (c:cs) -> (a, b, c) : zip3' as bs cs
  _ _ _ -> []

single :: Int -> String
single = \cases { 0 -> "zero"; n -> show n ++ suffix where suffix = "!" }

lazyArg :: Int -> Int -> Int
lazyArg = \cases
  0 _ -> 0
  n m -> n + m

main :: IO ()
main = do
  print (map (uncurry combine) [(Just 1, 2), (Just 5, -1), (Nothing, 9)])
  print (zip3' "abc" [1 :: Int ..] [True, False])
  putStrLn (single 0 ++ " " ++ single 7)
  print (lazyArg 0 undefined, (\cases a b -> (b, a)) 'x' 'y')
