-- Report 11.1: deriving Enum, Bounded, Ix and Read for
-- enumerations - constructor-tag arithmetic end to end.
import Data.Ix
import Text.Read

data Color = Red | Green | Blue | Violet
  deriving (Show, Eq, Ord, Enum, Bounded, Ix, Read)

main :: IO ()
main = do
  print [Red ..]
  print [Red, Blue ..]
  print (succ Red, pred Violet)
  print (fromEnum Blue, (toEnum 1 :: Color))
  print [Green .. Violet]
  print (minBound :: Color, maxBound :: Color)
  print (range (Red, Blue))
  print (index (Red, Violet) Blue, inRange (Green, Violet) Red)
  print (rangeSize (Green, Violet))
  print (read "Green" :: Color)
  print (reads "  Violet rest" :: [(Color, String)])
  print (reads "Chartreuse" :: [(Color, String)])
  print [minBound .. maxBound :: Color]
  print [False ..]
