import Data.Word
main :: IO ()
main = do
  print (fromEnum (2 ^ 63 - 1 :: Word64))
  print (fromEnum (2 ^ 63 :: Word64))
