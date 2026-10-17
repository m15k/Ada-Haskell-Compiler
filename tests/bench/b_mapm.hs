-- M150: mapM and sequence are Traversable methods. This pins their
-- cost over lists in Maybe and IO (the [] instance's direct monadic
-- mapM), which the class dispatch must not slow down.
step :: Int -> Maybe Int
step x = if x < 0 then Nothing else Just (x * 2)

main :: IO ()
main = do
  let xs = [1 .. 100000] :: [Int]
  print (fmap sum (mapM step xs))
  print (fmap length (sequence (map Just xs)))
  ys <- mapM (\x -> return (x + 1)) xs
  print (sum ys)
