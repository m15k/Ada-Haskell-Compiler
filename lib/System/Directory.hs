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

-- With parents, every missing prefix is created, an existing
-- DIRECTORY at any level is fine, and a FILE in the way is an error
-- (createDirectory's), as in the directory package.
createDirectoryIfMissing :: Bool -> FilePath -> IO ()
createDirectoryIfMissing parents p
  | parents   = mapM_ mkIfMissing (prefixes p)
  | otherwise = mkIfMissing p
  where
    mkIfMissing d = do
      e <- doesDirectoryExist d
      if e then return () else createDirectory d
    prefixes q = [ take n q | n <- [1 .. length q]
                            , n == length q || q !! n == '/'
                            , take n q /= "/" ]

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
