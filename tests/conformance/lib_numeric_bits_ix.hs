import Numeric
import Data.Bits
import Data.Ix

main :: IO ()
main = do
  putStrLn (showHex 48879 "")
  putStrLn (showOct 511 "")
  print (readHex "beefXY" :: [(Int, String)])
  print (readDec "123 rest" :: [(Int, String)])
  print (readOct "777" :: [(Int, String)])
  print (255 .&. 15 :: Int, 8 .|. 1 :: Int, xor 5 3 :: Int)
  print (shiftL 1 10 :: Int, shiftR 1024 3 :: Int, shift 7 (-1) :: Int)
  print (complement 0 :: Int, popCount (255 :: Int))
  print (testBit (5 :: Int) 0, testBit (5 :: Int) 1, setBit (0 :: Int) 4, clearBit (31 :: Int) 0)
  print (range (3, 7) :: [Int], range ('a', 'e'))
  print (index (3 :: Int, 7) 5, inRange (3 :: Int, 7) 9, rangeSize (3 :: Int, 7))
  print (index ('a', 'z') 'c', inRange ('a', 'z') 'q')
