-- Report 6.1.5-6.1.6: Maybe and Either with their eliminators.
main :: IO ()
main = do
  print (maybe 0 (+ 1) (Just 5), maybe 0 (+ 1) Nothing)
  print (either negate (* 2) (Left 3 :: Either Int Int))
  print (either negate (* 2) (Right 3 :: Either Int Int))
  print [Left 1, Right 'x', Left 2]
  print (Just (Left 5) :: Maybe (Either Int Bool))
