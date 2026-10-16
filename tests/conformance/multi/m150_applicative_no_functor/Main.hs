-- An Applicative instance needs a Functor instance (base's hierarchy).
newtype Parser a = Parser (String -> [(a, String)])

instance Applicative Parser where
  pure a = Parser (\s -> [(a, s)])
  Parser pf <*> Parser pa =
    Parser (\s -> [(f a, r2) | (f, r1) <- pf s, (a, r2) <- pa r1])

instance Monad Parser where
  Parser p >>= k = Parser (\s -> concat [q r | (a, r) <- p s, let Parser q = k a])

main :: IO ()
main = putStrLn "unreachable"
