data Port = Port (Int in 1 .. 65535) deriving (Eq, Ord)

newtype Volume = Volume (Int mod 256)

data Point = Point (Double in -90.0 .. 90.0) (Double in -180.0 .. 180.0)

positive :: Int -> Bool
positive n = n > 0

data Score = Score (Int satisfying positive)

portNum :: Port -> Int
portNum (Port n) = n

mkPoint :: Double -> Double -> Point
mkPoint = Point
