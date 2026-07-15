safeDiv :: Int -> Int -> Either String Int
safeDiv _ 0 = Left "divide by zero"
safeDiv a b = Right (a `div` b)
classify :: Int -> Maybe String
classify n
  | n > 0 = Just "positive"
  | n < 0 = Just "negative"
  | otherwise = Nothing
main = do
  print (safeDiv 10 2)
  print (safeDiv 1 0)
  print (map classify [-1, 0, 1])
  print (fromMaybe "none" (classify 0))
  print (all isJust (map classify [1, 2, 3]))
