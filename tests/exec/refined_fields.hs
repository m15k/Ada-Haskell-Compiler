data Port = Port (Int in 1 .. 65535) deriving (Eq, Ord)

newtype Volume = Volume (Int mod 256)

data Point = Point (Double in -90.0 .. 90.0) (Double in -180.0 .. 180.0)

positive :: Int -> Bool
positive n = n > 0

data Score = Score (Int satisfying positive)

portNum :: Port -> Int
portNum (Port n) = n

vol :: Volume -> Int
vol (Volume v) = v

lat :: Point -> Double
lat (Point a _) = a

points :: Score -> Int
points (Score s) = s

main :: IO ()
main = do
  print (portNum (Port 8080))
  print (map portNum (map Port [80, 443]))
  print (vol (Volume 300))
  print (lat (Point 45.5 120.0))
  print (points (Score 10))
  let bomb = Port 0 in print (const True bomb)
  print (portNum (Port 0))
