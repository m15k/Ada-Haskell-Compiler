-- IO failures raise catchable IOExceptions (M137): a missing file,
-- end of file, a closed handle, the wrong mode, a directory. Each
-- is read back field by field through the primitives, and the
-- values are GHC's (type index, location, description, filename).
import System.IO

fields :: SomeException -> (Int, String, String, Maybe String)
fields e = let i = primExcIO e
           in (primIoeType i, primIoeLocation i,
               primIoeDescription i, primIoeFilename i)

attempt :: IO () -> IO ()
attempt act = primCatch (act >> putStrLn "no exception")
                        (\e -> print (fields e))

main :: IO ()
main = do
  attempt (readFile "/nonexistent/zz.txt" >>= putStr)
  writeFile "/tmp/ahc_exc_io_test.txt" "one\n"
  h <- openFile "/tmp/ahc_exc_io_test.txt" ReadMode
  hGetLine h >>= putStrLn
  attempt (hGetLine h >>= putStrLn)            -- end of file
  attempt (hPutStr h "x")                      -- not open for writing
  hClose h
  hClose h                                     -- closing twice is fine (GHC agrees)
  attempt (hGetLine h >>= putStrLn)            -- handle is closed
  attempt (openFile "/nonexistent/dir/f" WriteMode >>= hClose)
  attempt (readFile "/tmp" >>= putStr)         -- a directory
  w <- openFile "/tmp/ahc_exc_io_test.txt" WriteMode
  attempt (hGetLine w >>= putStrLn)            -- not open for reading
  hClose w
  attempt (getLine >>= putStrLn)               -- stdin at end of file
  putStrLn "done"
