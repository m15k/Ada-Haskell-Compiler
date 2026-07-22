-- Applicative (base's class; the Report predates it): pure /
-- <*> / *> / <* / <$> at Maybe, [], and IO - a source Prelude
-- class over the wired Functor, defaults through liftA2.
main :: IO ()
main = do
  print (pure 3 :: Maybe Integer)
  print (Just (+ 2) <*> Just (40 :: Integer))
  print ((Nothing :: Maybe (Integer -> Integer)) <*> Just 1)
  print ([(+ 1), (* 10)] <*> [1, 2, 3 :: Integer])
  print (pure 'x' :: [Char])
  print ((,) <$> Just (1 :: Integer) <*> Just 'x')
  print (Just (3 :: Integer) *> Just 4)
  print ((Nothing :: Maybe Integer) *> Just 1)
  print ([1, 2 :: Integer] <* [10, 20, 30])
  print (negate <$> Just (5 :: Integer))
  v <- pure (99 :: Integer)
  print v
