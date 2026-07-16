-- Report 3.15: record construction, pattern matching, update,
-- field selectors.
data Rect = Rect { width :: Int, height :: Int } deriving (Eq)

area :: Rect -> Int
area (Rect { width = w, height = h }) = w * h

main :: IO ()
main = do
  let r = Rect { width = 3, height = 4 }
  print (area r)
  print (width r, height r)
  let r2 = r { height = 10 }
  print (area r2)
  print (r == r2)
  print (r2 == Rect { width = 3, height = 10 })
