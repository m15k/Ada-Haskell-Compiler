-- Marshal misuse dies cleanly: a poke value outside the width.
main :: IO ()
main = do
  p <- mallocBytes 8
  pokeInt8 p 0 300
  putStrLn "unreachable"
