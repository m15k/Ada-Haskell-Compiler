-- exitWith is an exception (kind 4, GHC agrees): a catch-all handler
-- sees it, and an uncaught one ends the program with its code and no
-- message. The harness compares output only; the exit code is
-- asserted by the trailing "unreached".
import System.Exit

main :: IO ()
main = do
  primCatch (exitWith (ExitFailure 3)) (\e -> print (primExcKind e, primExcCode e))
  primCatch exitSuccess (\e -> print (primExcKind e, primExcCode e))
  putStrLn "leaving with 7"
  exitWith (ExitFailure 7)
  putStrLn "unreached"
