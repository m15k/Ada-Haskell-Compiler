module Main where
import qualified U
data Box a = Box a | Empty deriving Show
instance Functor Box where
  fmap f (Box a) = Box (f a)
  fmap _ Empty = Empty
instance Applicative Box where
  pure = Box
  Box f <*> Box a = Box (f a)
  _ <*> _ = Empty
instance Monad Box where
  Box a >>= k = k a
  Empty >>= _ = Empty
instance U.Applicative Box where
  pure _ = Empty
main :: IO ()
main = print (return 5 :: Box Int)
