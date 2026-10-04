module System.Directory
  ( doesFileExist, doesDirectoryExist
  , listDirectory, getDirectoryContents
  , createDirectory, createDirectoryIfMissing
  , removeFile, removeDirectory, renameFile
  , getCurrentDirectory, setCurrentDirectory, getHomeDirectory
  ) where

-- System.Directory (M142): the everyday surface of the directory
-- package over POSIX. Failures are IOErrors with GHC's locations
-- ("removeLink", "getDirectoryContents:openDirStream", ...), so their
-- `show` matches; listings come in the OS's order, as GHC's do.

import System.IO.Error (tryIOError, isDoesNotExistError,
                        isAlreadyExistsError, isPermissionError)

doesFileExist :: FilePath -> IO Bool
doesFileExist = primFileExists

doesDirectoryExist :: FilePath -> IO Bool
doesDirectoryExist = primDirExists

getDirectoryContents :: FilePath -> IO [FilePath]
getDirectoryContents = primListDir

listDirectory :: FilePath -> IO [FilePath]
listDirectory p = fmap (filter (\n -> n /= "." && n /= "..")) (primListDir p)

createDirectory :: FilePath -> IO ()
createDirectory p = primPathOp p 0

-- The directory package's createDirectoryIfMissing: try the deepest
-- path first and climb only on "does not exist", so a FILE in the way
-- reports the path that mkdir refused ("inappropriate type (Not a
-- directory)"); an existing directory at the target is fine, an
-- existing file is createDirectory's "already exists".
createDirectoryIfMissing :: Bool -> FilePath -> IO ()
createDirectoryIfMissing parents p
  | parents   = createDirs (dirParents p)
  | otherwise = createDirs (take 1 (dirParents p))
  where
    createDirs [] = return ()
    createDirs [d] = createDir d ioError
    createDirs (d : ds) = createDir d (\_ -> createDirs ds >> createDir d ioError)
    createDir d notExist = do
      r <- tryIOError (createDirectory d)
      case r of
        Right () -> return ()
        Left e
          | isDoesNotExistError e -> notExist e
          | isAlreadyExistsError e || isPermissionError e -> do
              isDir <- doesDirectoryExist d
              if isDir then return () else ioError e
          | otherwise -> ioError e

-- The path and each of its ancestors, deepest first, after the
-- directory package's simplification (empty and "." components and
-- repeated or trailing slashes dropped).
dirParents :: FilePath -> [FilePath]
dirParents p = reverse (scanl1 join comps)
  where
    rooted = take 1 p == "/"
    parts = filter (\c -> c /= "" && c /= ".") (splitSlash p)
    comps = (if rooted then ("/" :) else id) parts
    join a b = if a == "/" then '/' : b else a ++ "/" ++ b
    splitSlash s = case break (== '/') s of
      (a, [])       -> [a]
      (a, _ : rest) -> a : splitSlash rest

removeFile :: FilePath -> IO ()
removeFile p = primPathOp p 1

removeDirectory :: FilePath -> IO ()
removeDirectory p = primPathOp p 2

setCurrentDirectory :: FilePath -> IO ()
setCurrentDirectory p = primPathOp p 3

renameFile :: FilePath -> FilePath -> IO ()
renameFile = primRename

getCurrentDirectory :: IO FilePath
getCurrentDirectory = primDirQuery 0

getHomeDirectory :: IO FilePath
getHomeDirectory = primDirQuery 1
