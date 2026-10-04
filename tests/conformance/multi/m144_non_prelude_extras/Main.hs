module Main where
-- AHC's Prelude also holds fromMaybe/isJust/swap, which GHC's does
-- not export: defining and using them is not ambiguous.
fromMaybe :: Int -> Maybe Int -> Int
fromMaybe d Nothing = d
fromMaybe _ (Just x) = x + 1

isJust :: Maybe a -> Bool
isJust _ = True

swap :: (a, b) -> (b, a)
swap (a, b) = (b, a)

main :: IO ()
main = do
  print (fromMaybe 0 (Just 5), isJust (Nothing :: Maybe Int))
  print (swap (1 :: Int, "x"))
