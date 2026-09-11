-- Report 4.3.1: a class method may carry its OWN context beyond the
-- class's. The dictionaries for it are arguments of the value stored
-- in the dictionary, so an instance's definition of that method takes
-- them too - until M141 the instance took the value arguments
-- directly while every call site applied the extra dictionary first,
-- and the program died "applied a non-function" at run time.
class Box t where
  wrap :: Show a => a -> t -> String
  unwrap :: (Show a, Eq a) => a -> a -> t -> String
  unwrap x y t = if x == y then wrap x t else wrap y t

instance Box Int where
  wrap x n = show x ++ "/" ++ show n

instance Box Bool where
  wrap x b = show x ++ "!" ++ show b
  unwrap x y b = wrap (x, y) b

newtype Tag = Tag String

instance Box Tag where
  wrap x (Tag s) = s ++ ":" ++ show x

main :: IO ()
main = do
  putStrLn (wrap (1 :: Int) (2 :: Int))
  putStrLn (wrap 'c' True)
  putStrLn (wrap [1, 2 :: Int] (Tag "list"))
  putStrLn (unwrap (3 :: Int) 3 (9 :: Int))
  putStrLn (unwrap 'a' 'b' False)
  putStrLn (concatMap (\t -> wrap t (0 :: Int)) ["x", "y"])
