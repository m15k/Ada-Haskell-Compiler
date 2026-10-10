newtype R e a = R (e -> a) deriving (Functor, Applicative, Monad)
run :: R e a -> e -> a
run (R f) = f
main :: IO ()
main = print (run (do { x <- R (+1); y <- R (*2); return (x + y) }) (10 :: Int))
