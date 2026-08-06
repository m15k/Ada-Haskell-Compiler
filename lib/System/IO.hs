module System.IO
  ( putStr, putStrLn, print
  , getLine, getContents, readFile, interact, isEOF
  , Handle, IOMode (ReadMode, WriteMode, AppendMode, ReadWriteMode)
  , stdin, stdout, stderr
  , openFile, hClose, withFile
  , hPutStr, hPutStrLn, hPutChar, hPrint
  , hGetLine, hGetChar, hGetContents, hIsEOF, hFlush
  , writeFile, appendFile
  , hPutText, hGetContentsText
  ) where

-- Handle is ABSTRACT: the constructor stays private, so the only
-- handles in circulation come from openFile and the std streams.
-- Underneath it is an index into the runtime's handle registry -
-- never a raw pointer, so operations on a closed handle fail with
-- a clean message instead of undefined behavior.
data Handle = MkHandle Int deriving (Eq)

data IOMode = ReadMode | WriteMode | AppendMode | ReadWriteMode
  deriving (Eq, Ord, Show, Enum)

stdin :: Handle
stdin = MkHandle 0

stdout :: Handle
stdout = MkHandle 1

stderr :: Handle
stderr = MkHandle 2

-- fromEnum IOMode matches the runtime's fopen-mode table
-- (0 "r", 1 "w", 2 "a", 3 "r+").
openFile :: String -> IOMode -> IO Handle
openFile path mode =
  primHOpen path (fromEnum mode) >>= \i -> return (MkHandle i)

-- On the std streams hClose flushes instead of closing (closing
-- stdout would break the runtime's own writers).
hClose :: Handle -> IO ()
hClose (MkHandle i) = primHClose i

withFile :: String -> IOMode -> (Handle -> IO a) -> IO a
withFile path mode act =
  openFile path mode >>= \h ->
  act h >>= \r ->
  hClose h >>
  return r

hPutStr :: Handle -> String -> IO ()
hPutStr (MkHandle i) s = primHPutStr i s

hPutStrLn :: Handle -> String -> IO ()
hPutStrLn h s = hPutStr h (s ++ "\n")

hPutChar :: Handle -> Char -> IO ()
hPutChar h c = hPutStr h [c]

hPrint :: Show a => Handle -> a -> IO ()
hPrint h x = hPutStrLn h (show x)

hGetLine :: Handle -> IO String
hGetLine (MkHandle i) = primHGetLine i

hGetChar :: Handle -> IO Char
hGetChar (MkHandle i) = primHGetChar i

-- Strict: the whole remaining contents are read at once (GHC's is
-- lazy with semi-closed handles; for read-then-use programs the
-- observable results agree).
hGetContents :: Handle -> IO String
hGetContents (MkHandle i) = primHGetContents i

-- Text IO at a Handle lives HERE, not in Data.Text: MkHandle is
-- private, and the wired-in Text type name needs no import. One
-- fwrite of the packed slice; input normalizes to valid UTF-8.
hPutText :: Handle -> Text -> IO ()
hPutText (MkHandle i) t = primTextHPut i t

hGetContentsText :: Handle -> IO Text
hGetContentsText (MkHandle i) = primTextHGetContents i

hIsEOF :: Handle -> IO Bool
hIsEOF (MkHandle i) = primHIsEOF i

hFlush :: Handle -> IO ()
hFlush (MkHandle i) = primHFlush i

writeFile :: String -> String -> IO ()
writeFile path s = withFile path WriteMode (\h -> hPutStr h s)

appendFile :: String -> String -> IO ()
appendFile path s = withFile path AppendMode (\h -> hPutStr h s)

interact :: (String -> String) -> IO ()
interact f = getContents >>= \s -> putStr (f s)
