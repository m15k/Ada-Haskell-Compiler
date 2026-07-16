-- Report 3.14: do expressions - binds, lets, sequencing.
main :: IO ()
main = do
  let a = 10
  putStrLn "start"
  let b = a + 5
      c = b * 2
  print (a, b, c)
  print (a + b + c)
  putStrLn "end"
