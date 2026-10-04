-- System.Directory (M142): create, list, test, rename, remove, and
-- GHC's error texts for the failing calls. Works in a fresh directory
-- under the current one and removes it again.
import System.Directory
import System.IO
import Control.Exception
import Data.List (sort, isSuffixOf)

say :: String -> IO ()
say s = putStrLn s >> hFlush stdout

attempt :: String -> IO () -> IO ()
attempt what act = do
  r <- try act
  case r of
    Left e  -> say (what ++ " failed: " ++ show (e :: IOException))
    Right _ -> say (what ++ " ok")

main :: IO ()
main = do
  let root = "m142_dir_tmp"
  createDirectoryIfMissing True (root ++ "/a/b")
  writeFile (root ++ "/a/f.txt") "hello"
  mapM_ (\p -> do { d <- doesDirectoryExist p; f <- doesFileExist p; say (p ++ " dir=" ++ show d ++ " file=" ++ show f) })
    [root ++ "/a", root ++ "/a/f.txt", root ++ "/missing"]
  sort <$> listDirectory (root ++ "/a") >>= say . show
  sort <$> getDirectoryContents (root ++ "/a") >>= say . show
  renameFile (root ++ "/a/f.txt") (root ++ "/a/g.txt")
  sort <$> listDirectory (root ++ "/a") >>= say . show
  attempt "createDirectory existing" (createDirectory (root ++ "/a"))
  attempt "removeDirectory non-empty" (removeDirectory (root ++ "/a"))
  attempt "removeFile missing" (removeFile (root ++ "/a/nope"))
  attempt "listDirectory missing" (listDirectory (root ++ "/zz") >> return ())
  attempt "renameFile missing" (renameFile (root ++ "/zz") (root ++ "/yy"))
  old <- getCurrentDirectory
  setCurrentDirectory root
  cwd <- getCurrentDirectory
  say ("cwd ends with root: " ++ show (root `isSuffixOf` cwd))
  setCurrentDirectory old
  removeFile (root ++ "/a/g.txt")
  removeDirectory (root ++ "/a/b")
  removeDirectory (root ++ "/a")
  removeDirectory root
  doesDirectoryExist root >>= say . ("root left behind: " ++) . show
  h <- getHomeDirectory
  say ("home non-empty: " ++ show (not (null h)))
