import Control.Exception
import Lib

t :: String -> IO () -> IO ()
t name act = do
  r <- try act
  case r of
    Left e -> putStrLn (name ++ " => " ++ show (e :: SomeException))
    Right () -> putStrLn (name ++ " ok")

main :: IO ()
main = do
  t "head in Lib" (evaluate (firstOf []) >> return ())
  t "error in Lib" (evaluate (failNow "no") >> return ())
  putStrLn "done"
