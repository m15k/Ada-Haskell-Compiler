newtype S = S !Int deriving Show
data DS = DS !Int deriving Show
main :: IO ()
main = do
  print (case S undefined of S _ -> "S lazy")
  print (case DS undefined of DS _ -> "DS lazy")
