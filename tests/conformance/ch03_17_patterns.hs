-- Report 3.17: pattern matching - wildcards, as-patterns, lazy
-- patterns, literal patterns, nested constructors.
firstTwo :: [Int] -> (Int, Int)
firstTwo all@(x : _) = case all of
  (_ : y : _) -> (x, y)
  _           -> (x, x)
firstTwo [] = (0, 0)

lazyPair :: (Int, Int) -> Int
lazyPair ~(a, _) = 5

isZero :: Int -> Bool
isZero 0 = True
isZero _ = False

unwrap :: Maybe (Maybe Int) -> Int
unwrap (Just (Just n)) = n
unwrap (Just Nothing)  = -1
unwrap Nothing         = -2

main :: IO ()
main = do
  print (firstTwo [7, 8, 9])
  print (firstTwo [7])
  print (isZero 0, isZero 3)
  print (unwrap (Just (Just 9)), unwrap (Just Nothing), unwrap Nothing)
  print (lazyPair (error "not forced", error "also not"))
