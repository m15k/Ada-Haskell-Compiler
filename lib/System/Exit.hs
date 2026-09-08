module System.Exit
  ( ExitCode (..), exitWith, exitSuccess, exitFailure
  ) where

data ExitCode = ExitSuccess | ExitFailure Int deriving (Eq, Show)

-- ExitFailure 0 is GHC's `exitWith: invalid argument (ExitFailure 0)`,
-- a catchable IOError (type index 10, docs/exceptions-design-note.md).
exitWith :: ExitCode -> IO a
exitWith ExitSuccess     = exitWithCode 0
exitWith (ExitFailure 0) =
  ioError (primMkIOError 10 "exitWith" "ExitFailure 0" Nothing)
exitWith (ExitFailure n) = exitWithCode n

exitSuccess :: IO a
exitSuccess = exitWithCode 0

exitFailure :: IO a
exitFailure = exitWithCode 1
