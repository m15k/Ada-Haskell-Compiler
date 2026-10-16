-- GHC 7.10's AMP: a Monad instance needs an Applicative instance.
newtype Parser a = Parser (String -> [(a, String)])

instance Functor Parser where
  fmap f (Parser p) = Parser (\s -> [(f a, r) | (a, r) <- p s])

instance Monad Parser where
  return a = Parser (\s -> [(a, s)])
  Parser p >>= k = Parser (\s -> concat [q r | (a, r) <- p s, let Parser q = k a])

main :: IO ()
main = putStrLn "unreachable"
