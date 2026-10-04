module System.Process
  ( system, rawSystem, callProcess, callCommand
  , readProcess, readProcessWithExitCode
  ) where

-- System.Process (M142): the process package's everyday calls over
-- posix_spawnp. Arguments go to the child as an argv vector, never
-- through a shell, except for `system` and `callCommand`, which are
-- defined to run `/bin/sh -c`. readProcess feeds stdin lazily and
-- captures stdout (stderr is inherited, as the process package);
-- readProcessWithExitCode captures both - drained together with the
-- feed, so no pipe deadlocks. Captured output must be UTF-8 (GHC's
-- hGetContents error otherwise). The runtime blocks while the child
-- runs (EXCLUSIONS). Exit by signal n is `ExitFailure (-n)`, as GHC.

import System.Exit

-- capture: bit 0 stdout, bit 1 stderr; an uncaptured stream and a
-- Nothing stdin are inherited.
spawn :: String -> [String] -> Int -> Maybe String
      -> IO (ExitCode, String, String)
spawn loc argv capture input = do
  (c, o, e) <- primProcRun loc argv capture input
  return (toExit c, o, e)

toExit :: Int -> ExitCode
toExit 0 = ExitSuccess
toExit n = ExitFailure n

system :: String -> IO ExitCode
system "" = ioError (primMkIOError 10 "system" "null command" Nothing)
system cmd = do
  (c, _, _) <- spawn "system" ["/bin/sh", "-c", cmd] 0 Nothing
  return c

rawSystem :: String -> [String] -> IO ExitCode
rawSystem prog args = do
  (c, _, _) <- spawn "rawSystem" (prog : args) 0 Nothing
  return c

callProcess :: FilePath -> [String] -> IO ()
callProcess prog args = do
  (c, _, _) <- spawn "callProcess" (prog : args) 0 Nothing
  failed "callProcess" (prog ++ concatMap ((' ' :) . show) args) c

callCommand :: String -> IO ()
callCommand cmd = do
  (c, _, _) <- spawn "callCommand" ["/bin/sh", "-c", cmd] 0 Nothing
  failed "callCommand" cmd c

readProcess :: FilePath -> [String] -> String -> IO String
readProcess prog args input = do
  (c, o, _) <- spawn "readCreateProcess" (prog : args) 1 (Just input)
  failed "readCreateProcess" (prog ++ concatMap ((' ' :) . show) args) c
  return o

readProcessWithExitCode :: FilePath -> [String] -> String
                        -> IO (ExitCode, String, String)
readProcessWithExitCode prog args input =
  spawn "readCreateProcessWithExitCode" (prog : args) 3 (Just input)

-- The process package's processFailedException: an OtherError whose
-- location is "<fun>: <cmd> (exit <n>)", shown as "...: failed".
failed :: String -> String -> ExitCode -> IO ()
failed _ _ ExitSuccess = return ()
failed fun cmd (ExitFailure n) =
  ioError (primMkIOError 9 (fun ++ ": " ++ cmd ++ " (exit " ++ show n ++ ")") "" Nothing)
