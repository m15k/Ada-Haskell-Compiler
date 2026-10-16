-- Report 4.1.2: the tuple type constructors (,), (,,), ... are
-- ordinary type constructors, usable prefix and partially applied -
-- in signatures and in instance heads (M150, for base's ((,) a)).
newtype Wrap f a = Wrap (f a)

pairT :: (,) Int Bool
pairT = (1, True)

tripleT :: (,,) Int Char Bool
tripleT = (1, 'x', False)

unwrap :: Wrap ((,) String) Int -> (String, Int)
unwrap (Wrap p) = p

class Tag f where
  tag :: f b -> String

instance Show a => Tag ((,) a) where
  tag (a, _) = "pair:" ++ show a

instance Tag ((,,) a b) where
  tag _ = "triple"

main :: IO ()
main = do
  print (pairT, tripleT)
  print (unwrap (Wrap ("k", 2)))
  putStrLn (tag (1 :: Int, 'x'))
  putStrLn (tag ('a', "b", True))
