module System.Exit
  ( ExitCode (..), exitWith, exitSuccess, exitFailure
  ) where

data ExitCode = ExitSuccess | ExitFailure Int deriving (Eq, Show)

exitWith :: ExitCode -> IO a
exitWith ExitSuccess     = exitWithCode 0
exitWith (ExitFailure n) = exitWithCode (if n == 0 then 1 else n)

exitSuccess :: IO a
exitSuccess = exitWithCode 0

exitFailure :: IO a
exitFailure = exitWithCode 1
