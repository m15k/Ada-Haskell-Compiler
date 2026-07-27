-- The Foreign.Marshal surface: raw memory, byte offsets, every
-- width, pointer arithmetic, and C-string round trips.
main :: IO ()
main = do
  p <- mallocBytes 32
  pokeInt64 p 0 4242
  pokeInt8 p 8 (-7)
  pokeWord32 p 12 3000000000
  pokeDouble p 16 2.5
  a <- peekInt64 p 0
  b <- peekInt8 p 8
  c <- peekWord32 p 12
  d <- peekDouble p 16
  print (a, b, c, d)
  let q = plusPtr p 8
  b2 <- peekInt8 q 0
  print b2
  pokePtr p 24 q
  q2 <- peekPtr p 24
  print (q2 == castPtr q)
  s <- newCString "marshal"
  n <- peekCStringLen s 7
  putStrLn n
  free s
  free p
