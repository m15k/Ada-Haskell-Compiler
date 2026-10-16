-- M150: an Ix index out of range shows GHC 9.4.8's text for the index
-- type - Ix{Int}/Ix{Char}/Ix{Integer} name the type and print the
-- index and bounds, while the fixed-width types, pairs and derived
-- instances say "Error in array index" - plus the Integer and pair
-- instances' range/index/inRange/rangeSize.
import Control.Exception
import Data.Ix
import Data.Int
import Data.Word

data T = A | B | C | D deriving (Show, Eq, Ord, Ix)

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
  t "Int" (f (index (0, 2 :: Int) 5))
  t "Int negative" (f (index (-3, -1 :: Int) 0))
  t "Char" (f (index ('a', 'c') 'z'))
  t "Integer" (f (index (0, 2 :: Integer) 5))
  t "Integer big" (f (index (0, 2 :: Integer) (2 ^ 70)))
  t "pair" (f (index ((0, 0), (1, 1) :: (Int, Int)) (2, 0)))
  t "pair of Char" (f (index (('a', 'a'), ('b', 'b')) ('a', 'z')))
  t "derived" (f (index (A, B) D))
  t "Int8" (f (index (0, 2 :: Int8) 5))
  t "Int64" (f (index (0, 2 :: Int64) 5))
  t "Word8" (f (index (0, 2 :: Word8) 5))
  t "Word64" (f (index (0, 2 :: Word64) 5))
  print (range (3, 6 :: Integer), index (3, 6 :: Integer) 5)
  print (inRange (3, 6 :: Integer) 7, rangeSize (3, 6 :: Integer), rangeSize (6, 3 :: Integer))
  print (range ((0, 0), (1, 2) :: (Int, Int)))
  print (map (index ((0, 0), (1, 2) :: (Int, Int))) [(0, 0), (0, 2), (1, 0), (1, 2)])
  print (inRange ((0, 0), (1, 2) :: (Int, Int)) (1, 3), rangeSize ((0, 0), (1, 2) :: (Int, Int)))
  print (rangeSize ((0, 5), (3, 2) :: (Int, Int)), range ((1, 'a'), (2, 'b') :: (Integer, Char)))
  print (index ((1, 'a'), (2, 'b') :: (Integer, Char)) (2, 'a'))
