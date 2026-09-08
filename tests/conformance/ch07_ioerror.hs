-- Report 9 (the Prelude's IOError, ioError, userError) with the
-- Report's own way of catching one, System.IO.Error.catchIOError.
import System.IO.Error (catchIOError, ioeGetErrorString, isUserError)

main :: IO ()
main = do
  r <- catchIOError (ioError (userError "custom failure") >> return "no")
                    (\e -> return ("caught: " ++ show e))
  putStrLn r
  catchIOError (ioError (userError "second"))
               (\e -> do putStrLn (ioeGetErrorString e)
                         print (isUserError e))
  print (userError "x" == userError "x", userError "x" == userError "y")
  print (userError "")
  print [userError "in a list"]
  -- not raised until run: building the action is pure
  let act = ioError (userError "built, not run")
  putStrLn "built"
  catchIOError (act >> putStrLn "unreached") (\e -> putStrLn ("ran: " ++ show e))
