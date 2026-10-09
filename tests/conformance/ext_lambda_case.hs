{-# LANGUAGE LambdaCase #-}
-- \case, always on in AHC (M147), oracled against GHC 9.4.8.
classify :: Int -> String
classify = \case
  0 -> "zero"
  n | n < 0 -> "negative"
    | even n -> "even"
  _ -> "odd"

firstJust :: [Maybe a] -> Maybe a
firstJust = foldr (\case { Just x -> const (Just x); Nothing -> id }) Nothing

depth :: [Either Int String] -> [Int]
depth = map $ \case
  Left n -> n * 2
  Right s -> length s
  where _unused = ()

nested :: Maybe (Maybe Int) -> Int
nested = \case
  Just inner -> (\case Just v -> v; Nothing -> -1) inner
  Nothing -> -2

main :: IO ()
main = do
  mapM_ (putStrLn . classify) [0, -3, 4, 7]
  print (firstJust [Nothing, Just 'a', Just 'b'], firstJust ([] :: [Maybe Int]))
  print (depth [Left 3, Right "four"], map nested [Just (Just 5), Just Nothing, Nothing])
  r <- (\case { [] -> return 0; xs -> return (sum xs) }) [1, 2, 3 :: Int]
  print r
