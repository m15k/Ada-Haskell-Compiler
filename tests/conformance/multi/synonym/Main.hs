import Defs

look :: String -> Env -> Integer
look k e =
  case lookup k e of
    Just v -> v
    Nothing -> negate 1

names :: Table Bool -> [String]
names t = map fst t

main :: IO ()
main = do
  let e = extend "b" 2 (extend "a" 1 none)
  print (look "a" e, look "b" e, look "c" e)
  print (names [("x", True), ("y", False)])
