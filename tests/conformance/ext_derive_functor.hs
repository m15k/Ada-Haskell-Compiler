{-# LANGUAGE DeriveFunctor #-}
-- Stock DeriveFunctor, always on in AHC (M148).
data Pair a = Pair a a deriving (Show, Functor)
data Tree a = Leaf | Node (Tree a) a (Tree a) deriving (Show, Functor)
data Rec a = Rec { tag :: Int, val :: a, vals :: [a] } deriving (Show, Functor)
data Wrap f a = Wrap (f a) (Maybe (f a)) deriving Functor
data Tup a = Tup (Int, a) (a, Bool) deriving (Show, Functor)
data Fn a = Fn (Int -> a) deriving Functor

newtype Parser a = Parser (String -> [(a, String)]) deriving Functor
data Phantom t a = Phantom a deriving (Show, Functor)

runFn :: Fn a -> Int -> a
runFn (Fn f) = f

runP :: Parser a -> String -> [(a, String)]
runP (Parser p) = p

main :: IO ()
main = do
  print (fmap (+ 1) (Pair 1 2), fmap show (Node Leaf 3 (Node Leaf 4 Leaf)))
  print (fmap negate (Rec 7 1 [2, 3]), fmap not (Tup (0, True) (False, True)))
  let Wrap a b = fmap (* 10) (Wrap [1, 2] (Just [3]))
  print (a, b)
  print (runFn (fmap (* 2) (Fn (+ 1))) 5, runP (fmap length (Parser (\s -> [(s, "")]))) "abc")
  print (fmap (++ "!") (Phantom "p" :: Phantom Bool String), (+ 1) <$> Leaf)
