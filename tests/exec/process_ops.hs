-- System.Process (M142): exit codes, argv passed without a shell,
-- stdin/stdout/stderr through pipes (a large stdin, to prove no
-- deadlock), a signal, and GHC's error texts.
import System.Process
import System.Exit
import System.IO
import Control.Exception

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
  system "echo from-shell" >>= say . show
  rawSystem "/bin/echo" ["a b", "c"] >>= say . show
  system "exit 3" >>= say . show
  readProcess "/bin/cat" [] "piped\n" >>= say . show
  readProcessWithExitCode "/bin/sh" ["-c", "echo out; echo err 1>&2; exit 4"] "" >>= say . show
  big <- readProcess "/bin/cat" [] (concat (replicate 20000 "0123456789\n"))
  say ("big: " ++ show (length big))
  errOnly <- readProcessWithExitCode "/bin/sh" ["-c", "head -c 300000 /dev/zero | tr '\\0' x 1>&2"] ""
  say (case errOnly of (c, o, e) -> show (c, length o, length e))
  system "kill -9 $$" >>= say . show
  attempt "callProcess false" (callProcess "/usr/bin/false" [])
  attempt "callCommand exit 2" (callCommand "exit 2")
  attempt "readProcess failing" (readProcess "/bin/sh" ["-c", "exit 5"] "" >> return ())
  attempt "missing executable" (callProcess "/no/such/program" ["x"])
  attempt "rawSystem missing" (rawSystem "/no/such/program" [] >>= say . show)
