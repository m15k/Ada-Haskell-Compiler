-- The classic: libc's qsort sorting a C array with a HASKELL
-- comparator - wrapper callback + marshal surface + fixed-width
-- types, all in one golden.
{-# LANGUAGE ForeignFunctionInterface #-}

foreign import ccall "qsort" c_qsort
  :: Ptr a -> CSize -> CSize
  -> FunPtr (Ptr a -> Ptr a -> IO CInt) -> IO ()
foreign import ccall "wrapper" mkCmp
  :: (Ptr a -> Ptr a -> IO CInt)
  -> IO (FunPtr (Ptr a -> Ptr a -> IO CInt))

pokeList :: Ptr a -> Int -> [Int] -> IO ()
pokeList _ _ [] = return ()
pokeList p i (x : xs) = do
  pokeInt64 p (8 * i) (fromIntegral x)
  pokeList p (i + 1) xs

peekList :: Ptr a -> Int -> Int -> IO [Int64]
peekList p i n =
  if i == n
    then return []
    else do
      x <- peekInt64 p (8 * i)
      xs <- peekList p (i + 1) n
      return (x : xs)

main :: IO ()
main = do
  let xs = [42, -7, 1000000000000, 3, -99, 0, 7] :: [Int]
      n = length xs
  p <- mallocBytes (8 * n)
  pokeList p 0 xs
  cmp <- mkCmp (\pa pb -> do
                  a <- peekInt64 pa 0
                  b <- peekInt64 pb 0
                  return (if a < b then -1
                          else if a > b then 1 else 0))
  c_qsort p (fromIntegral n) 8 cmp
  ys <- peekList p 0 n
  print ys
  freeHaskellFunPtr cmp
  free p
