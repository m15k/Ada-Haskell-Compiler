-- M142 review: a function type never unifies with an application of a
-- type constructor other than (->). Both compilers reject.
x :: Maybe Int
x = id

f :: Either String Int -> Int
f g = g 3

main :: IO ()
main = print (f (Right 1))
