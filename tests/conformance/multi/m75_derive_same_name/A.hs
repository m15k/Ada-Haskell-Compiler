module A (Shape (..), mk) where
data Shape = Circle Int | Square Int
  deriving (Show, Eq, Ord)
mk :: Int -> Shape
mk = Circle
