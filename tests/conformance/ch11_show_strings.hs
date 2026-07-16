-- Report 11.4: show at String/Char via showList; escapes; shows and
-- showsPrec; negative-literal parenthesization.
main :: IO ()
main = do
  print "hello"
  print "tab\there \"quoted\" back\\slash"
  print (Just "abc")
  print (Just (-5))
  print (Just (Just 3))
  print (Just (Left (-2)) :: Maybe (Either Int Bool))
  print ["ab", "cd", ""]
  print (showsPrec 11 (-3) "")
  print (shows 42 "!")
  print ('a', "bc", [1, 2])
  print (showParen True (showString "x") "")
