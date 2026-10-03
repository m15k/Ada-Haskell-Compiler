module Left (Shape (..), area) where
data Shape = Circle Double | Square Double
area :: Shape -> Double
area (Circle r) = 3.0 * r * r
area (Square s) = s * s
