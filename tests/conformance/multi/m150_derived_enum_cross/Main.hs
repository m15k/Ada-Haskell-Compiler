-- M150 D3: a derived Enum in an imported module locates its errors
-- at that module's deriving clause.
import Control.Exception
import Shapes

data Local = One | Two deriving (Show, Enum)

t :: String -> a -> IO ()
t name v = do
  r <- try (evaluate v)
  case r of
    Left e -> putStrLn (name ++ " => " ++ show (e :: SomeException))
    Right _ -> putStrLn (name ++ " => no error")

main :: IO ()
main = do
  t "succ Square" (succ Square)
  t "pred Small" (pred Small)
  t "toEnum 5 :: Size" (toEnum 5 :: Size)
  t "succ Two" (succ Two)
  print [Circle ..]
