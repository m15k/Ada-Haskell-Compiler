-- Library Report 42, System.IO.Error: the failures the runtime
-- raises (missing file, end of file, a closed handle, the wrong
-- mode, a directory), every predicate and accessor, and IOErrors
-- built and edited by hand.
import System.IO
import System.IO.Error
import System.Exit

describe :: IOError -> IO ()
describe e = do
  print e
  print (ioeGetErrorType e)
  putStrLn (ioeGetErrorString e)
  print (ioeGetLocation e, ioeGetFileName e)
  print [isAlreadyExistsError e, isDoesNotExistError e, isAlreadyInUseError e,
         isFullError e, isEOFError e, isIllegalOperation e,
         isPermissionError e, isUserError e]

attempt :: IO () -> IO ()
attempt act = tryIOError act >>= either describe (const (putStrLn "no error"))

main :: IO ()
main = do
  attempt (readFile "/nonexistent/ahc/zz.txt" >>= putStr)
  attempt (writeFile "/nonexistent/ahc/dir/out.txt" "x")
  attempt (readFile "/tmp" >>= putStr)
  writeFile "/tmp/ahc_conf_ioerror.txt" "only line\n"
  h <- openFile "/tmp/ahc_conf_ioerror.txt" ReadMode
  hGetLine h >>= putStrLn
  attempt (hGetLine h >>= putStrLn)
  attempt (hPutStr h "x")
  hClose h
  hClose h
  attempt (hGetLine h >>= putStrLn)
  w <- openFile "/tmp/ahc_conf_ioerror.txt" WriteMode
  attempt (hGetLine w >>= putStrLn)
  hClose w
  attempt (ioError (userError "plain user error"))
  attempt (exitWith (ExitFailure 0))          -- GHC: a catchable invalid-argument IOError
  attempt (ioError (userError ""))
  -- built and edited by hand
  let e0 = mkIOError doesNotExistErrorType "myLocation" Nothing (Just "f.txt")
  print e0
  print (ioeSetErrorString e0 "custom string")
  print (ioeSetLocation e0 "elsewhere")
  print (ioeSetFileName e0 "g.txt")
  print (ioeSetErrorType e0 eofErrorType)
  print (annotateIOError (userError "base") "loc2" Nothing (Just "fn"))
  print (annotateIOError e0 "loc3" Nothing (Just "ignored"))
  print (mkIOError userErrorType "u" Nothing Nothing)
  print [alreadyExistsErrorType, doesNotExistErrorType, alreadyInUseErrorType,
         fullErrorType, eofErrorType, illegalOperationErrorType,
         permissionErrorType, userErrorType]
  print [isAlreadyExistsErrorType alreadyExistsErrorType,
         isDoesNotExistErrorType doesNotExistErrorType,
         isAlreadyInUseErrorType alreadyInUseErrorType,
         isFullErrorType fullErrorType, isEOFErrorType eofErrorType,
         isIllegalOperationErrorType illegalOperationErrorType,
         isPermissionErrorType permissionErrorType,
         isUserErrorType userErrorType, isEOFErrorType userErrorType]
  print (e0 == e0, e0 == ioeSetLocation e0 "x")
  -- modifyIOError rewrites on the way out
  r <- tryIOError (modifyIOError (\e -> ioeSetLocation e "modified")
                                 (ioError (userError "m")))
  either print (const (putStrLn "no error")) r
  -- an unrelated exception passes catchIOError untouched
  r2 <- tryIOError (catchIOError (ioError (userError "inner"))
                                 (\e -> ioError (ioeSetErrorString e "rethrown")))
  either print (const (putStrLn "no error")) r2
