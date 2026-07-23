main :: IO ()
main = print (length (show (product [1 .. 2000 :: Integer])))
