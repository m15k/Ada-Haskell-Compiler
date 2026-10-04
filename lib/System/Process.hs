module System.Process
  ( system, rawSystem, callProcess, callCommand
  , readProcess, readProcessWithExitCode
  ) where

-- System.Process (M142): the process package's everyday calls over
-- posix_spawnp. Arguments go to the child as an argv vector, never
-- through a shell, except for `system` and `callCommand`, which are
-- defined to run `/bin/sh -c`. readProcess feeds stdin and drains
-- stdout and stderr together (no deadlock on either pipe). The
-- runtime blocks while the child runs (EXCLUSIONS). Exit by signal n
-- is `ExitFailure (-n)`, as GHC.

import System.Exit

spawn :: String -> [String] -> Maybe String -> IO (ExitCode, String, String)
spawn loc argv input = do
  (c, o, e) <- primProcRun loc argv input
  return (toExit c, o, e)

toExit :: Int -> ExitCode
toExit 0 = ExitSuccess
toExit n = ExitFailure n

system :: String -> IO ExitCode
system cmd = do
  (c, _, _) <- spawn "system" ["/bin/sh", "-c", cmd] Nothing
  return c

rawSystem :: String -> [String] -> IO ExitCode
rawSystem prog args = do
  (c, _, _) <- spawn "rawSystem" (prog : args) Nothing
  return c

callProcess :: FilePath -> [String] -> IO ()
callProcess prog args = do
  (c, _, _) <- spawn "callProcess" (prog : args) Nothing
  failed "callProcess" (prog ++ concatMap ((' ' :) . show) args) c

callCommand :: String -> IO ()
callCommand cmd = do
  (c, _, _) <- spawn "callCommand" ["/bin/sh", "-c", cmd] Nothing
  failed "callCommand" cmd c

readProcess :: FilePath -> [String] -> String -> IO String
readProcess prog args input = do
  (c, o, _) <- spawn "readCreateProcess" (prog : args) (Just input)
  failed "readCreateProcess" (prog ++ concatMap ((' ' :) . show) args) c
  return o

readProcessWithExitCode :: FilePath -> [String] -> String
                        -> IO (ExitCode, String, String)
readProcessWithExitCode prog args input =
  spawn "readCreateProcessWithExitCode" (prog : args) (Just input)

-- The process package's processFailedException: an OtherError whose
-- location is "<fun>: <cmd> (exit <n>)", shown as "...: failed".
failed :: String -> String -> ExitCode -> IO ()
failed _ _ ExitSuccess = return ()
failed fun cmd (ExitFailure n) =
  ioError (primMkIOError 9 (fun ++ ": " ++ cmd ++ " (exit " ++ show n ++ ")") "" Nothing)
