-- Report ch. 7 / System.IO: file handles. Write, append, and read
-- back through explicit handles; IOMode's derived instances; std
-- streams compare by identity. Self-contained: writes only under
-- /tmp. Portability rule learned writing this: never touch a
-- handle after hGetContents (GHC semi-closes it), and force
-- everything you need from a withFile action INSIDE the action
-- (GHC's lazy hGetContents escapes the close otherwise).
import System.IO

path :: String
path = "/tmp/ahc_conformance_io.txt"

main :: IO ()
main = do
  h <- openFile path WriteMode
  hPutStrLn h "line one"
  hPutStr h "line "
  hPutStrLn h "two"
  hPutChar h 'x'
  hPutChar h '\n'
  hClose h
  appendFile path "appended\n"
  r <- openFile path ReadMode
  l1 <- hGetLine r
  putStrLn l1
  c <- hGetChar r
  print c
  e <- hIsEOF r
  print e
  rest <- hGetContents r
  putStr rest
  hClose r
  s <- readFile path
  putStr s
  n <- withFile path ReadMode (\hh -> hGetLine hh >>= \l -> return (length l))
  print n
  writeFile path "overwritten\n"
  s2 <- readFile path
  putStr s2
  hPrint stdout ReadMode
  print [ReadMode ..]
  print (ReadMode < WriteMode, ReadMode == ReadMode)
  print (stdout == stdout, stdin == stdout)
  hFlush stdout
