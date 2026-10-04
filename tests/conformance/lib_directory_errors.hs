-- System.Directory's error texts (the M142 review round): renameFile
-- refuses a directory on either side, createDirectoryIfMissing names
-- the path a file blocks, setCurrentDirectory reports at
-- changeWorkingDirectory. Runs in a scratch directory it removes.
import System.Directory
import Control.Exception
import System.IO.Error

t :: String -> IO () -> IO ()
t name act = do
  r <- try act
  case r of
    Left e -> putStrLn (name ++ ": " ++ show (e :: IOException)
                        ++ " | " ++ show (isDoesNotExistError e, isAlreadyExistsError e, isPermissionError e, ioeGetFileName e))
    Right () -> putStrLn (name ++ ": ok")

main :: IO ()
main = do
  createDirectory "dir_errors_wd"
  createDirectory "dir_errors_wd/d"
  createDirectory "dir_errors_wd/d2"
  writeFile "dir_errors_wd/f.txt" "x"
  writeFile "dir_errors_wd/g.txt" "y"
  t "rename dir src" (renameFile "dir_errors_wd/d" "dir_errors_wd/e")
  t "rename dir src onto file" (renameFile "dir_errors_wd/d" "dir_errors_wd/f.txt")
  t "rename file onto dir" (renameFile "dir_errors_wd/f.txt" "dir_errors_wd/d2")
  t "rename missing" (renameFile "dir_errors_wd/nope" "dir_errors_wd/x")
  t "rename missing onto dir" (renameFile "dir_errors_wd/nope" "dir_errors_wd/d2")
  t "rename file into missing dir" (renameFile "dir_errors_wd/f.txt" "dir_errors_wd/nodir/x")
  t "rename ok" (renameFile "dir_errors_wd/g.txt" "dir_errors_wd/h.txt")
  doesFileExist "dir_errors_wd/h.txt" >>= print
  t "mkdir -p through a file" (createDirectoryIfMissing True "dir_errors_wd/f.txt/sub")
  t "mkdir -p through a file, deeper" (createDirectoryIfMissing True "dir_errors_wd/f.txt/sub/deeper")
  t "mkdir -p onto a file" (createDirectoryIfMissing True "dir_errors_wd/f.txt")
  t "mkdir onto a file" (createDirectoryIfMissing False "dir_errors_wd/f.txt")
  t "mkdir -p ok" (createDirectoryIfMissing True "dir_errors_wd/a/b/c")
  t "mkdir -p trailing slash" (createDirectoryIfMissing True "dir_errors_wd/a/b/c2/")
  t "mkdir -p exists" (createDirectoryIfMissing True "dir_errors_wd/a/b")
  doesDirectoryExist "dir_errors_wd/a/b/c" >>= print
  t "mkdir missing parent" (createDirectoryIfMissing False "dir_errors_wd/q/r")
  t "cd missing" (setCurrentDirectory "dir_errors_wd/nope")
  t "cd file" (setCurrentDirectory "dir_errors_wd/f.txt")
  mapM_ removeDirectory ["dir_errors_wd/a/b/c", "dir_errors_wd/a/b/c2", "dir_errors_wd/a/b", "dir_errors_wd/a", "dir_errors_wd/d", "dir_errors_wd/d2"]
  mapM_ removeFile ["dir_errors_wd/f.txt", "dir_errors_wd/h.txt"]
  removeDirectory "dir_errors_wd"
