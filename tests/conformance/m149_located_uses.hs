-- M149: located Prelude functions are found by identity. A module's
-- own `head` is not the Prelude's, so its error carries only error's
-- own call stack; an unapplied or qualified use of the Prelude's head
-- is located at the use; (!!) in a section too.
import Prelude hiding (head)
import qualified Prelude as P
import Control.Exception

head :: [a] -> a
head (x : _) = x
head [] = error "my head: empty"

t :: String -> IO () -> IO ()
t name act = do
  r <- try act
  case r of
    Left e -> putStrLn (name ++ " => " ++ show (e :: SomeException))
    Right () -> putStrLn (name ++ " ok")

main :: IO ()
main = do
  t "own head" (evaluate (head ([] :: [Int])) >> return ())
  t "qualified" (evaluate (P.head ([] :: [Int])) >> return ())
  t "unapplied" (evaluate (sum (map P.head [[1], [] :: [Int]])) >> return ())
  t "section" (evaluate ((!! 3) [1, 2 :: Int]) >> return ())
  t "error in where" (evaluate (f 0) >> return ())
  putStrLn "done"
  where
    f :: Int -> Int
    f 0 = error "zero"
    f n = n
