-- An uncaught ExitCode exception exits with its code and prints
-- nothing: the top-level handler GHC has.
main :: IO ()
main = do
  putStrLn "before"
  primThrowIO (primExcExit 0)
  putStrLn "unreached"
