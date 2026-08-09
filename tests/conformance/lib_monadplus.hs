-- Control.Monad's Alternative-era surface: guard, MonadPlus (whose
-- instances are empty-bodied -- both methods default), msum, mfilter.
-- Also pins mapM/sequence living in the Prelude (Report 8) and
-- return defaulting to pure when a Monad instance omits it.
import Control.Monad

newtype Ident a = Ident { runIdent :: a }

instance Functor Ident where
  fmap f (Ident x) = Ident (f x)

instance Applicative Ident where
  pure x = Ident x
  Ident f <*> Ident x = Ident (f x)

instance Monad Ident where
  Ident x >>= k = k x
  -- no return: defaults to pure

pyth :: Int -> [(Int, Int, Int)]
pyth n = do
  a <- [1 .. n]
  b <- [a .. n]
  c <- [b .. n]
  guard (a * a + b * b == c * c)
  return (a, b, c)

-- A user class whose instance body is empty: every method a default.
class Greet a where
  greet :: a -> String
  greet _ = "hello"

data Unit = Unit

instance Greet Unit

main :: IO ()
main = do
  print (pyth 20)
  print (guard True :: Maybe ())
  print (guard False :: Maybe ())
  print (mzero :: [Int])
  print (mplus (Just 1) (Just 2))
  print (mplus Nothing (Just 2))
  print (msum [Nothing, Just 7, Just 8])
  print (mfilter even (Just 4))
  print (mfilter even (Just 5))
  print (mfilter odd [1, 2, 3, 4, 5])
  print (runIdent (mapM (\x -> Ident (x * 2)) [1, 2, 3]))
  print (sequence [Just 1, Just 2])
  print (sequence [Just 1, Nothing])
  putStrLn (greet Unit)
