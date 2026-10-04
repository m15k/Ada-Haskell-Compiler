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
  , BufferMode (..), hSetBuffering, hGetBuffering, hSetEcho, hGetEcho
  ) where

import Control.Exception (bracket)

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

-- GHC's withFile: the handle is closed when the body raises, and
-- any IOError escaping - from the open or from the body - is
-- reported at "withFile" with THIS file's name, replacing whatever
-- name it carried, as GHC's addFilePathToIOError does (readFile's own stays
-- at "openFile": the probe in docs/exceptions-design-note.md). The
-- relabel goes through the primitives directly: System.IO.Error
-- imports THIS module for Handle, so it cannot be imported here.
withFile :: String -> IOMode -> (Handle -> IO a) -> IO a
withFile path mode act =
  primCatch (bracket (openFile path mode) hClose act) (\se ->
    if primExcKind se == 3
      then let e = primExcIO se
           in primThrowIO (primExcFromIO
                (primMkIOError (primIoeType e) "withFile"
                               (primIoeDescription e) (Just path)))
      else primThrowIO se)

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
-- private, and the wired-in Text type comes from the library's whole Prelude. One
-- fwrite of the packed slice; input normalizes to valid UTF-8.
hPutText :: Handle -> Text -> IO ()
hPutText (MkHandle i) t = primTextHPut i t

hGetContentsText :: Handle -> IO Text
hGetContentsText (MkHandle i) = primTextHGetContents i

hIsEOF :: Handle -> IO Bool
hIsEOF (MkHandle i) = primHIsEOF i

hFlush :: Handle -> IO ()
hFlush (MkHandle i) = primHFlush i

-- Buffering and echo (M142, found by the repo scout: interactive
-- programs open with `hSetBuffering stdout NoBuffering`, and hangman
-- hides the word with hSetEcho).
data BufferMode = NoBuffering | LineBuffering | BlockBuffering (Maybe Int)
  deriving (Eq, Ord, Read, Show)

hSetBuffering :: Handle -> BufferMode -> IO ()
hSetBuffering (MkHandle i) m = primHSetBuffering i code
  where
    code = case m of
      NoBuffering              -> 1
      LineBuffering            -> 2
      BlockBuffering Nothing   -> 3
      BlockBuffering (Just n)  -> if n <= 0 then 3 else 3 + n

hGetBuffering :: Handle -> IO BufferMode
hGetBuffering (MkHandle i) = fmap decode (primHGetBuffering i)
  where
    decode 1 = NoBuffering
    decode 2 = LineBuffering
    decode 3 = BlockBuffering Nothing
    decode n = BlockBuffering (Just (n - 3))

hSetEcho :: Handle -> Bool -> IO ()
hSetEcho (MkHandle i) b = primHSetEcho i b

hGetEcho :: Handle -> IO Bool
hGetEcho (MkHandle i) = primHGetEcho i
