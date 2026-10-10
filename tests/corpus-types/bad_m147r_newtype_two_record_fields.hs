newtype R = R { ra :: Int, rb :: Int } deriving Show
main :: IO ()
main = print (rb (R 1 2))
