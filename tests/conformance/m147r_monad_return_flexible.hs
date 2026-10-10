newtype P s a = P (s -> (a, s))
run :: P s a -> s -> (a, s)
run (P f) = f
instance Functor (P Int) where fmap f (P g) = P (\s -> let (a, s') = g s in (f a, s'))
instance Applicative (P Int) where
  pure a = P (\s -> (a, s))
  P f <*> P g = P (\s -> let (h, s1) = f s; (a, s2) = g s1 in (h a, s2))
instance Monad (P Int) where
  P g >>= k = P (\s -> let (a, s1) = g s in run (k a) s1)
tick :: P Int Int
tick = P (\s -> (s, s + 1))
main :: IO ()
main = print (fst (run (do { a <- tick; b <- tick; return (a + b) }) 10))
