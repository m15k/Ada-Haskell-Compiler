module U (Applicative (..), twice) where
import Prelude hiding (Applicative (..))
class Applicative f where
  pure :: a -> f a
twice :: Int -> Int
twice x = 2 * x
