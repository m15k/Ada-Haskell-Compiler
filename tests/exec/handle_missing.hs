-- openFile on a missing file dies cleanly with the path.
import System.IO

main :: IO ()
main = do
  putStrLn "start"
  h <- openFile "/tmp/ahc_no_such_file_ever.txt" ReadMode
  hGetLine h >>= putStrLn
