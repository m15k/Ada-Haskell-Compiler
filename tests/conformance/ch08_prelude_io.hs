-- Report 7: basic IO - putStr, putStrLn, print sequencing.
main :: IO ()
main = do
  putStr "a"
  putStr "b"
  putStrLn "c"
  putStrLn ""
  putStrLn "line"
  print 'd'
  mapM_ print [1, 2, 3]
