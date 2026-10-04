-- main's RESULT is never demanded (GHC runs main for its effects):
-- ahc_run_main used to force it, so `return undefined` as the last
-- action died after the output (M142 review).
main :: IO ()
main = do
  putStrLn "effects ran"
  return undefined
