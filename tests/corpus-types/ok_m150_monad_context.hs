-- M150: under Monad m alone, Functor and Applicative come by
-- superclass extraction, as GHC's base has them since 7.10.
pairUp :: Monad m => m a -> m b -> m (a, b)
pairUp ma mb = (,) <$> ma <*> mb

bump :: Monad m => m Int -> m Int
bump = fmap (+ 1)

walk :: Monad m => (a -> m b) -> Maybe a -> m (Maybe b)
walk = mapM

main :: IO ()
main = print (pairUp (Just 1) (bump (Just (2 :: Int))), walk Just (Just 'x'))
