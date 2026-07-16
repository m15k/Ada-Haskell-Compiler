-- Prelude list functions (Report ch. 9 specification).
main :: IO ()
main = do
  print (map (* 2) [1, 2, 3])
  print (filter odd [1 .. 9])
  print (foldr (:) [] [1, 2, 3])
  print (foldl (-) 100 [1, 2, 3])
  print (reverse [1 .. 5])
  print (length [10, 20, 30], null [], null [1])
  print (head [1, 2], tail [1, 2, 3], last [1, 2, 3], init [1, 2, 3])
  print (take 2 [1 .. 9], drop 6 [1 .. 9])
  print (concat [[1], [2, 3], []])
  print (concatMap (\x -> [x, x]) [1, 2])
