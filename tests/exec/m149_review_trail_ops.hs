infixl 6 <+>
(<+>) :: Int -> Int -> Int
a <+> b = a `div` b

go' :: Int -> Int
go' n = n <+> 0

cafe :: Int -> Int
cafe x = go' x

(?\) :: Int -> Int -> Int
a ?\ b = cafe (a + b)

main :: IO ()
main = print (3 ?\ 4)
