module Right (Shape (..), area) where
data Shape = Circle Int | Square Int
  deriving (Show, Eq)
area :: Shape -> Int
area (Circle r) = 3 * r * r
area (Square s) = s * s
