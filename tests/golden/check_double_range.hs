type Latitude = Double in -90.0 .. 90.0
type Unit = Double in 0 .. 1

move :: Latitude -> Double -> Latitude
move lat d = lat + d

blend :: Unit -> Double -> Double -> Double
blend t a b = (1 - t) * a + t * b

speed :: Double in 0.0 .. 3.0e2
speed = 88.5
