-- M149: a failing value with nested constructors, a string and a
-- negative number, all evaluated before the failure.
data Item = Item String Int deriving Show
data Order = Order Item [Int] | Empty deriving Show

total :: Order -> Int
total Empty = 0

main :: IO ()
main = do
  let o = Order (Item "lamp" (-2)) [1, 2, 3]
  print o
  print (total o)
