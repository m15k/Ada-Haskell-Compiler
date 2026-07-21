module System.IO
  ( putStr, putStrLn, print
  , getLine, getContents, readFile, interact, isEOF
  ) where

interact :: (String -> String) -> IO ()
interact f = getContents >>= \s -> putStr (f s)
