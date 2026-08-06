-- An embedded \NUL is data: the literal must not truncate at it.
main :: IO ()
main = do
  let s = "a\NULb"
  print (length s)
  print (map fromEnum s)
  putStrLn s
