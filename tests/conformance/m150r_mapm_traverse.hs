import Control.Monad (ap, liftM)
newtype T m a = T { runT :: m (Maybe a) }
instance Functor m => Functor (T m) where fmap f (T m) = T (fmap (fmap f) m)
instance Monad m => Applicative (T m) where pure = T . return . Just; (<*>) = ap
instance Monad m => Monad (T m) where
  T m >>= k = T (m >>= maybe (return Nothing) (runT . k))
class Monad m => MonadLog m where logS :: String -> m ()
instance MonadLog IO where logS = putStrLn
newtype U m a = U { runU :: m a }
instance Functor f => Functor (U f) where fmap f (U m) = U (fmap f m)
instance Applicative f => Applicative (U f) where pure = U . pure; U f <*> U x = U (f <*> x)
instance MonadLog m => Monad (U m) where U m >>= k = U (logS "b" >> m >>= runU . k)
main = do
  r <- runT (mapM (\x -> T (print x >> return (Just x))) [1,2,3])
  print r
  r2 <- runU (forM' [1,2] (\x -> U (return (x * 2))))
  print r2
  where forM' xs f = mapM f xs
