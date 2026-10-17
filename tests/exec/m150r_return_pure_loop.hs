import Control.Monad (ap)
newtype P a = P a
instance Functor P where fmap f (P a) = P (f a)
instance Applicative P where
               pure = return; (<*>) = ap
instance Monad P where
  P a >>= k = k a
unP (P a) = a
main = do
  putStrLn "start"
  print (unP (P 1 >>= \x -> return (x + 1)))
