-- Report 2.6: character and string literals beyond ASCII. Chars are
-- Unicode code points: one list element per code point, decimal
-- escapes and raw source characters agree, IO round-trips UTF-8.
main :: IO ()
main = do
  print (length "\955")
  print ("\955" == "λ")
  print ('λ' == '\955')
  print (map fromEnum "λä漢👍")
  print (fromEnum 'é', toEnum 233 :: Char)
  putStrLn "λä漢👍"
  print "\955"
  print "\955\&5"
  print 'λ'
  print (show "λx5")
  l <- getLine
  print (length l, map fromEnum l)
  putStrLn (reverse l)
  print (words "α β γ")
