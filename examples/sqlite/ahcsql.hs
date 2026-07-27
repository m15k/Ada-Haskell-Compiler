-- ahcsql: AHC binding a real C library - sqlite3, which ships with
-- the OS. Everything the FFI has crosses the boundary here: an
-- out-parameter through mallocBytes/peekPtr, strings both ways,
-- fixed-width CInt results, a Haskell row callback handed to
-- sqlite3_exec as a C function pointer, nullPtr/nullFunPtr, and
-- the C library's own error message peeked back on failure.
{-# LANGUAGE ForeignFunctionInterface #-}
{-# OPTIONS_AHC_LINK -lsqlite3 #-}

type ExecCB = Ptr () -> CInt -> Ptr (Ptr Char) -> Ptr (Ptr Char)
              -> IO CInt

foreign import ccall "sqlite3_open" c_open
  :: String -> Ptr a -> IO CInt
foreign import ccall "sqlite3_close" c_close :: Ptr a -> IO CInt
foreign import ccall "sqlite3_errmsg" c_errmsg
  :: Ptr a -> IO (Ptr Char)
foreign import ccall "sqlite3_exec" c_exec
  :: Ptr a -> String -> FunPtr ExecCB -> Ptr b -> Ptr c -> IO CInt
foreign import ccall "wrapper" mkCB :: ExecCB -> IO (FunPtr ExecCB)

-- One column: NULL-safe C string fetch from a char** at index i.
field :: Ptr (Ptr Char) -> Int -> IO String
field arr i = do
  p <- peekPtr arr (8 * i)
  if p == nullPtr then return "NULL" else peekCString p

fields :: CInt -> Ptr (Ptr Char) -> Ptr (Ptr Char) -> Int
       -> IO [String]
fields n argv cols i =
  if i == fromIntegral n
    then return []
    else do
      name <- field cols i
      val <- field argv i
      rest <- fields n argv cols (i + 1)
      return ((name ++ "=" ++ val) : rest)

joinComma :: [String] -> String
joinComma [] = ""
joinComma [x] = x
joinComma (x : xs) = x ++ ", " ++ joinComma xs

sql :: Ptr a -> String -> IO CInt
sql db q = c_exec db q nullFunPtr nullPtr nullPtr

main :: IO ()
main = do
  pp <- mallocBytes 8
  rc <- c_open ":memory:" pp
  db <- peekPtr pp 0
  free pp
  putStrLn ("open rc=" ++ show rc)

  _ <- sql db "CREATE TABLE langs (name TEXT, year INT)"
  _ <- sql db ("INSERT INTO langs VALUES"
               ++ " ('Haskell', 1990), ('Ada', 1980), ('C', 1972)")

  cb <- mkCB (\_ n argv cols -> do
                fs <- fields n argv cols 0
                putStrLn (joinComma fs)
                return 0)
  rcQ <- c_exec db "SELECT name, year FROM langs ORDER BY year"
                cb nullPtr nullPtr
  putStrLn ("query rc=" ++ show rcQ)
  freeHaskellFunPtr cb

  rcBad <- sql db "SELECT * FROM missing"
  if rcBad /= 0
    then do
      em <- c_errmsg db
      s <- peekCString em
      putStrLn ("sqlite error: " ++ s)
    else putStrLn "unexpected success"

  rcC <- c_close db
  putStrLn ("close rc=" ++ show rcC)
