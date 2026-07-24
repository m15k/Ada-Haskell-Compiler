-- Error paths: a missing file dies with a clean message; so does
-- an operation on a closed handle (the registry catches it - no
-- freed FILE pointer is ever touched).
import System.IO

main :: IO ()
main = do
  putStrLn "start"
  h <- openFile "/tmp/ahc_handle_err_test.txt" WriteMode
  hPutStrLn h "data"
  hClose h
  r <- openFile "/tmp/ahc_handle_err_test.txt" ReadMode
  hClose r
  l <- hGetLine r
  putStrLn l
  putStrLn "unreached"
