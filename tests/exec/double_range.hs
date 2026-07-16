type Latitude = Double in -90.0 .. 90.0
type Unit = Double in 0 .. 1

move :: Latitude -> Double -> Latitude
move lat d = lat + d

blend :: Unit -> Double -> Double -> Double
blend t a b = (1 - t) * a + t * b

main :: IO ()
main = do
  print (move 45.0 20.5)
  print (move (-89.5) (-0.5))
  print (blend 0.25 10 20)
  print ((0.5 :: Unit))
  print (7 / 2 :: Double)
  print (move 80.0 15.0)
