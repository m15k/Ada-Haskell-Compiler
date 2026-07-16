-- Report 3.8/6.1.4: unit and tuples.
main :: IO ()
main = do
  print ()
  print (1, 'a')
  print (1, 2, 3)
  print (fst (1, 'x'), snd (1, 'x'))
  print ((1, 2), (3, (4, 5)))
  print (curry fst 7 8)
  print (uncurry (+) (3, 4))
