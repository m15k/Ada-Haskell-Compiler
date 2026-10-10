newtype A = A B deriving (Eq)
newtype B = B A deriving (Eq)
main :: IO ()
main = print (A undefined == A undefined)
