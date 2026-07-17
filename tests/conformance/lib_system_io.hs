import System.IO
import System.Exit
import Control.Monad (when, forM_)
import Data.Char (toUpper)

main :: IO ()
main = do
  l1 <- getLine
  putStrLn (map toUpper l1)
  l2 <- getLine
  rest <- getContents
  putStrLn (l2 ++ "|" ++ show (length rest))
  forM_ [1, 2] print
  when False exitFailure
  putStrLn "done"
