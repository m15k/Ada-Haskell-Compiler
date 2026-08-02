-- Report 9.1 Prelude: (!!) at infixl 9, the FilePath synonym, and the
-- Read class with reads/read exported from the Prelude (no import).
describe :: FilePath -> String
describe p = "file:" ++ p

data Colour = Red | Green | Blue deriving (Show, Read, Eq)

main :: IO ()
main = do
  print ([10, 20, 30] !! 0)
  print ([10, 20, 30] !! 2)
  print ("abcde" !! 4)
  print ([[1], [2, 3]] !! 1 !! 1)
  print (1 + [10, 20] !! 1)
  putStrLn (describe "/tmp/x")
  print (read "42" :: Int)
  print (read "  -17  " :: Integer)
  print (read "True" :: Bool)
  print (read "[1,2,3]" :: [Int])
  print (read "(1,True)" :: (Int, Bool))
  print (read "Green" :: Colour)
  print (reads "12 rest" :: [(Int, String)])
  print (reads "nope" :: [(Int, String)])
