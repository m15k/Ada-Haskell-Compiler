-- M150: the show of a caught error from Data.Array, Data.Char,
-- Numeric, Data.List/Data.Foldable's maximumBy/minimumBy and
-- Data.Ratio is GHC 9.4.8's, byte for byte (base raises these with
-- errorWithoutStackTrace, or as ArithException), and maximumBy keeps
-- the LAST of equal greatest elements, as base's does.
import Control.Exception
import qualified Data.Foldable as F
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.Array
import Data.Char (digitToInt, intToDigit)
import Data.List (maximumBy, minimumBy)
import Data.Ord (comparing)
import Data.Ratio
import Numeric (showHex, showIntAtBase)

t :: String -> IO () -> IO ()
t name act = do
  r <- try act
  case r of
    Left e -> putStrLn (name ++ " => " ++ show (e :: SomeException))
    Right () -> putStrLn (name ++ " ok")

f :: a -> IO ()
f x = evaluate x >> return ()

main :: IO ()
main = do
  t "Array ! high" (f (listArray (0, 2) "abc" ! (5 :: Int)))
  t "Array ! low" (f (listArray (0, 2) "abc" ! (-1 :: Int)))
  t "Array undefined element" (f (array (0, 2) [(0, 'a')] ! (1 :: Int)))
  t "Array short list" (f (listArray (0, 2) "a" ! (2 :: Int)))
  t "showIntAtBase negative" (f (length (showIntAtBase 10 intToDigit (-1) "")))
  t "showIntAtBase base 1" (f (length (showIntAtBase 1 intToDigit 5 "")))
  t "showHex negative" (f (length (showHex (-255 :: Int) "")))
  t "digitToInt" (f (digitToInt 'z'))
  t "intToDigit" (f (intToDigit 20))
  t "intToDigit negative" (f (intToDigit (-1)))
  t "maximumBy" (f (maximumBy compare ([] :: [Int])))
  t "minimumBy" (f (minimumBy compare ([] :: [Int])))
  t "maximumBy Maybe" (f (F.maximumBy compare (Nothing :: Maybe Int)))
  t "minimumBy Set" (f (F.minimumBy compare (Set.empty :: Set.Set Int)))
  t "ratio zero" (f (1 % (0 :: Integer)))
  t "recip zero" (f (recip (0 :: Rational)))
  r <- try (evaluate (3 % (0 :: Int)))
  putStrLn (either (\e -> "ArithException: " ++ show (e :: ArithException))
                   show r)
  -- the values the same functions return when they succeed
  print (listArray (0, 2) "abc" ! (2 :: Int), showIntAtBase 2 intToDigit 10 "")
  print (map digitToInt "09afAF", map intToDigit [0, 9, 10, 15])
  -- ties: maximumBy keeps the LAST greatest, minimumBy the FIRST least
  let xs = [(1, 'a'), (3, 'b'), (3, 'c'), (1, 'd')] :: [(Int, Char)]
  print (maximumBy (comparing fst) xs, minimumBy (comparing fst) xs)
  print (F.maximumBy (comparing negate) (Map.fromList [(1 :: Int, 5 :: Int), (2, 9), (3, 9)]))
  print (F.maximumBy (comparing (`mod` 3)) (Set.fromList [1 .. 10 :: Int]))
  print (F.minimumBy compare (Just 'q'), 6 % (4 :: Int), recip (3 % 4 :: Rational))
