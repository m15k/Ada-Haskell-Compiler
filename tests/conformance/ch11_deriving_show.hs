-- Report 11.5: derived Show instances.
data Color = Red | Green | Blue deriving (Eq, Ord, Show)
data Shape = Circle Int | Rect Int Int deriving Show
data Box a = Box a deriving Show
data Pt = Pt { px :: Int, py :: Int } deriving Show

main :: IO ()
main = do
  print [Red, Green, Blue]
  print (Rect 3 4)
  print (Circle (-5))
  print (Just (Circle 5))
  print (Box (Just [1, 2]))
  print (Box "str")
  print (Pt { px = 1, py = -2 })
  print [Box 1, Box 2]
