module B (Shape (..), mk) where
data Shape = Circle Double Double | Tri
  deriving (Show, Eq, Ord)
mk :: Double -> Shape
mk d = Circle d d
