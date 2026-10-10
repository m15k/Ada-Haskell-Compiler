newtype Y a = Y [Maybe a] deriving (Eq, Ord)
main :: IO ()
main = print (Y [Just 1] < Y [Nothing])
