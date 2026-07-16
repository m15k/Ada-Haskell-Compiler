-- Prelude combinators: id, const, flip, composition, application.
main :: IO ()
main = do
  print (id 42)
  print (const 1 (error "never forced"))
  print (flip (-) 1 10)
  print ((negate . (+ 1)) 4)
  print (negate $ 3 + 4)
  print (map (negate . negate) [1, 2])
  print (until (> 100) (* 2) 1)
