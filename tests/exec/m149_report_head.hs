-- M149: head [] is reported at the user's call, not inside base.
firstWord :: String -> String
firstWord s = head (words s)

main :: IO ()
main = do
  putStrLn (firstWord "hello world")
  putStrLn (firstWord "")
