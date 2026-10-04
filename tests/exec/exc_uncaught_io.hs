-- An uncaught IOException prints GHC's show text after "ahc: " -
-- the one renderer the Show instance in the Prelude mirrors.
import AHC.Prim
main :: IO ()
main = do
  putStrLn "before"
  primThrowIO (primExcFromIO (primMkIOError 1 "openFile"
                                "No such file or directory" (Just "f.txt")))
  putStrLn "unreached"
