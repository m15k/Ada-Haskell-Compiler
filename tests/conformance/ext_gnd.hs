{-# LANGUAGE GeneralizedNewtypeDeriving #-}
-- GND, always on in AHC (M147): every class but Show/Read derives
-- through the representation's instance.
newtype Age = Age Int
  deriving (Show, Read, Eq, Ord, Bounded, Enum, Num, Real, Integral)
newtype Score = Score Double deriving (Show, Eq, Ord, Num, Fractional)
newtype W a = W (Maybe a) deriving (Show, Eq, Functor)
newtype Box a = Box [a] deriving (Show, Functor, Semigroup, Monoid)
newtype Counter a = Counter (Either String a) deriving (Show, Functor, Applicative, Monad)

tick :: Counter Int -> Counter Int
tick c = do
  n <- c
  if n > 2 then Counter (Left "too big") else return (n + 1)

main :: IO ()
main = do
  print (Age 3 + 4, Age 10 `div` 3, [Age 1 .. Age 3], maxBound :: Age)
  print (read "Age 7" :: Age, toInteger (Age 9), succ (Age 5), fromIntegral (Age 2) + (1 :: Int))
  print (Score 1.5 * 2, recip (Score 4), Score 1 < Score 2)
  print (fmap (+ 1) (W (Just 1)), W (Just 'a') == W (Just 'a'))
  print (Box [1, 2] <> Box [3], mempty :: Box Int, fmap show (Box [True]))
  print (tick (Counter (Right 1)), tick (tick (tick (Counter (Right 1)))))
