-- Report 3.14: only a bind whose pattern can FAIL uses `fail`.
-- Wildcards, variables, lazy patterns, tuples, and single-constructor
-- products need no fail continuation, so they typecheck in ANY monad
-- - including one with no useful fail - and inside a polymorphic
-- Monad m function, where an unused, Monad-constrained continuation
-- would otherwise be ambiguous.
data Box = Box Int

newtype Ident a = Ident { runIdent :: a }

instance Functor Ident where
  fmap f (Ident x) = Ident (f x)

instance Applicative Ident where
  pure = Ident
  Ident f <*> Ident x = Ident (f x)

instance Monad Ident where
  Ident x >>= k = k x

sumUp :: Monad m => m Int -> m (Int, Int) -> m Box -> m Int
sumUp mx mp mb = do
  _ <- mx
  x <- mx
  (a, b) <- mp
  Box c <- mb
  ~(d, e) <- mp
  return (x + a + b + c + d + e)

main :: IO ()
main = do
  print (runIdent (sumUp (Ident 1) (Ident (2, 3)) (Ident (Box 4))))
  r <- sumUp (return 10) (return (20, 30)) (return (Box 40))
  print r
  -- a failable pattern still fails through `fail` where the monad has one
  print (do { Just v <- [Just 1, Nothing, Just 3]; return (v :: Int) })
