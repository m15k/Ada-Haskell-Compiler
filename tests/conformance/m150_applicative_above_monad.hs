-- M150 phase C: Applicative is Monad's superclass (GHC 7.10's AMP), so
-- a Monad m context alone gives pure, <*>, fmap, *>, <* and liftA2;
-- return defaults to pure; <*> defaults to liftA2 id.
import Control.Applicative (liftA2)

-- Only Monad m in scope: Functor and Applicative come by superclass.
pairUp :: Monad m => m a -> m b -> m (a, b)
pairUp ma mb = (,) <$> ma <*> mb

bump :: Monad m => m Int -> m Int
bump m = fmap (+ 1) m

both :: Monad m => m a -> m b -> m b
both ma mb = ma *> mb

firstOf :: Monad m => m a -> m b -> m a
firstOf ma mb = ma <* mb

lifted :: Monad m => m Int -> m Int -> m Int
lifted = liftA2 (+)

pureIn :: Monad m => a -> m [a]
pureIn x = pure [x, x]

-- A state monad whose Monad instance omits return: base's default
-- return = pure applies.
newtype St s a = St { runSt :: s -> (a, s) }

instance Functor (St s) where
  fmap f (St g) = St (\s -> let (a, s') = g s in (f a, s'))

instance Applicative (St s) where
  pure a = St (\s -> (a, s))
  St f <*> St g = St (\s -> let (h, s1) = f s; (a, s2) = g s1 in (h a, s2))

instance Monad (St s) where
  St g >>= k = St (\s -> let (a, s1) = g s in runSt (k a) s1)

tick :: St Int Int
tick = St (\s -> (s, s + 1))

-- An Applicative that defines liftA2 and not <*>: base's default
-- (<*>) = liftA2 id applies.
newtype Box a = Box a deriving Show

instance Functor Box where
  fmap f (Box a) = Box (f a)

instance Applicative Box where
  pure = Box
  liftA2 f (Box a) (Box b) = Box (f a b)

instance Monad Box where
  Box a >>= k = k a

main :: IO ()
main = do
  print (pairUp (Just 1) (Just 'a'))
  print (pairUp [1, 2] "xy")
  print (bump (Right 41 :: Either String Int))
  print (both (Just 1) (Just 2), both Nothing (Just 2 :: Maybe Int))
  print (firstOf [1, 2] "ab")
  print (lifted (Just 2) (Just 3))
  print (pureIn 'z' :: Maybe String)
  r <- pairUp (return 1) (putStrLn "effect" >> return True)
  print (r :: (Int, Bool))
  print (fst (runSt (do { a <- tick; b <- tick; return (a + b) }) 10))
  print (fst (runSt (pairUp tick (fmap (* 100) tick)) 1))
  print (Box (+ 1) <*> Box 41)
  print (do { x <- Box 2; y <- pure 3; return (x * y) })
  print (Box 'a' *> Box 'b', Box 'a' <* Box 'b')
