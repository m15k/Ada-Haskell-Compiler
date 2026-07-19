import Data.Array
import Text.Read

main :: IO ()
main = do
  let a = listArray (0, 3) "wxyz"
  print a
  print (a ! 2, bounds a, elems a)
  print (indices a, assocs a)
  let b = array (1, 3) [(3, 30), (1, 10), (2, 20)]
  print b
  print (b // [(2, 99)])
  print (read "42" :: Int)
  print (read " -17 " :: Integer)
  print (read "(-3)" :: Int)
  print (read "True" :: Bool)
  print (read "[1,2,3]" :: [Int])
  print (read "[]" :: [Int])
  print (read "(1,2)" :: (Int, Int))
  print (read "[(1,2),(3,4)]" :: [(Int, Int)])
  print (reads "12 rest" :: [(Int, String)])
