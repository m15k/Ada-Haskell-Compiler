module System.IO
  ( putStr, putStrLn, print
  , getLine, getContents, readFile, interact
  ) where

interact :: (String -> String) -> IO ()
interact f = getContents >>= \s -> putStr (f s)
