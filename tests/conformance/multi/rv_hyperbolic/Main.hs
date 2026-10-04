main = do
  let xs = [0, -0.0, 1, -1, 0.5, -0.5, 1e10, -1e10, 1e200, -1e200, 1e-10, -1e-10, 2, 0.99999999] :: [Double]
  mapM_ (\x -> print (x, asinh x)) xs
  mapM_ (\x -> print (x, acosh x)) [1, 2, 1e10, 1e200, 0.5, -1 :: Double]
  mapM_ (\x -> print (x, atanh x)) [0, -0.0, 0.5, -0.5, 1, -1, 1e-10, 2 :: Double]
