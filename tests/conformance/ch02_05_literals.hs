-- Report 2.5: numeric literals in all radices; character escapes.
main :: IO ()
main = do
  print (255 :: Int)
  print (0xFF :: Int)
  print (0o777 :: Int)
  print (0x10 + 0o10 + 10)
  print 'x'
  print '\n'
  print '\\'
  print '\''
  putStrLn "tab:\there"
  putStrLn "quote:\"q\""
  print (negate 42)
