-- PRE on a named transition fires inside the protected action.
import Control.Concurrent.Protected

{-# PRE  push \x s -> length s < 3 #-}
{-# POST push \x s (s', _) -> length s' <= 3 #-}
push :: Int -> [Int] -> ([Int], ())
push x s = (s ++ [x], ())

main :: IO ()
main = do
  p <- newProtected []
  updating p (push 1)
  updating p (push 2)
  updating p (push 3)
  n <- reading p length
  print n
  putStrLn "now violate"
  updating p (push 4)
  putStrLn "unreached"
