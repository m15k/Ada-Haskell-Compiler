-- A derived Ix instance's index checks inRange, as GHC's (M146
-- review: index (A, B) D returned 2). GHC: 1, then "Error in array
-- index" (AHC prints its ahc: error: banner, EXCLUSIONS row 9).
import Data.Ix
data T = A | B | C | D deriving (Show, Eq, Ord, Ix)
main :: IO ()
main = do
  print (index (A, C) B, inRange (A, B) D, rangeSize (B, D))
  print (index (A, B) D)
