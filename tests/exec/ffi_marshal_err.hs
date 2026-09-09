-- A poke value beyond the width wraps like GHC's (M139): 300 :: Int8
-- is 44, and that is what lands in memory. (Until M139 the value
-- stayed 300 and died at the boundary: "poke: value out of range".)
main :: IO ()
main = do
  p <- mallocBytes 8
  pokeInt8 p 0 300
  peekInt8 p 0 >>= print
  pokeWord8 p 1 (-1)
  peekWord8 p 1 >>= print
