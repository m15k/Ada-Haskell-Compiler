import Control.Exception
import Data.Array
main = do
  r <- try (evaluate (foldr1 (+) (listArray (1, 0) [] :: Array Int)))
  case r of
    Left e -> putStrLn (show (e :: SomeException))
    Right v -> print v
