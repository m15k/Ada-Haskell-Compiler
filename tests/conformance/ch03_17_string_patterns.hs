-- Report 3.17: string literals in pattern position, including the
-- empty string -- the base case of any string-recursive function.
classify :: String -> String
classify "" = "empty"
classify "a" = "one-a"
classify ('a' : _) = "starts-a"
classify _ = "other"

trimL :: String -> String
trimL "" = ""
trimL (c : cs) = if c == ' ' then trimL cs else c : cs

countEmpty :: [String] -> Int
countEmpty xs = length [() | x <- xs, isEmpty x]
  where isEmpty "" = True
        isEmpty _ = False

-- The same test as a case alternative rather than an equation.
asCase :: String -> Int
asCase s = case s of
  "" -> 0
  "q" -> 1
  _ -> 2

main :: IO ()
main = do
  print (map classify ["", "a", "ab", "zz"])
  print (map trimL ["", "  hi", "no"])
  print (countEmpty ["", "x", "", "y"])
  print (map asCase ["", "q", "zz"])
