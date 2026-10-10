main :: IO ()
main = do
  print ((\cases -> cases + 1) (2::Int))
  print (map (\ cases -> cases * 2) [1,2::Int])
