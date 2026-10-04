-- Double/Float comparisons with NaN (M142 review): == and the four
-- relational operators are IEEE (False), compare answers GT for an
-- unordered pair either way round, as GHC's Ord Double does; max, min,
-- sort, elem and derived structural equality follow from those.
import Data.List (sort, sortBy, nub)
main :: IO ()
main = do
  let nan = 0 / 0 :: Double
      fnan = 0 / 0 :: Float
  print (nan == nan, nan /= nan, 1 == nan, nan == 1)
  print (compare nan 1, compare 1 nan, compare nan nan)
  print (nan < 1, nan <= 1, nan > 1, nan >= 1)
  print (1 < nan, 1 <= nan, 1 > nan, 1 >= nan)
  print (max nan 1, max 1 nan, min nan 1, min 1 nan)
  print (elem nan [nan], nan `elem` [1, 2], lookup nan [(nan, 'x')])
  print (sort [3, nan, 1, 2], sort [nan, 2, 1])
  print (maximum [1, nan, 3], minimum [1, nan, 3])
  print ((nan, 1 :: Int) == (nan, 1), compare (1 :: Int, nan) (1, 2))
  print (Just nan == Just nan, [nan] == [nan], nub [nan, nan])
  print (fnan == fnan, compare fnan 1, fnan > 1, fnan >= 1, max fnan 1)
  print (compare (1 :: Double) 2, compare (2 :: Double) 2, 3 > (2 :: Double), 2 >= (2 :: Double))
