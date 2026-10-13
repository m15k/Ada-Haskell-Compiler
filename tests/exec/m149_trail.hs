-- M149: ahc build --trail. The uncaught report (or plain error) ends
-- with the most recent traced evaluations, newest first, a repeat
-- folded into a count. Built with tests/exec/m149_trail.flags.
data Shape = Circle Double | Square Double | Triangle Double Double

area :: Shape -> Double
area (Circle r) = pi * r * r
area (Square s) = s * s

total :: [Shape] -> Double
total = sum . map area

ratio :: Int -> Int -> Int
ratio a b = a `div` b

main :: IO ()
main = do
  print (total [Circle 1, Square 2])
  print (ratio 10 (length (filter (> 5) [1, 2, 3])))
