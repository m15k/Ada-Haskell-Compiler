import Data.Array
import Control.Exception
t :: String -> a -> IO ()
t lbl x = do
  r <- try (evaluate x)
  case r of
    Left e -> putStrLn (lbl ++ " => EXC: " ++ show (e :: SomeException))
    Right _ -> putStrLn (lbl ++ " => ok")
main = do
  t "empty !" ((listArray (1,0) [] :: Array Char) ! 0)
  t "no elems, oob" ((listArray (0,4) [] :: Array Char) ! 9)
  t "no elems, neg" ((listArray (0,4) [] :: Array Char) ! (-1))
  t "array [] oob" ((array (0,2) [] :: Array Char) ! 7)
