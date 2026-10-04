module L where
helper :: Int -> Int
helper = (+ 1)
data T = MkT Int deriving Show
data Shape = Circle Int deriving Show
class Named a where
  name :: a -> String
