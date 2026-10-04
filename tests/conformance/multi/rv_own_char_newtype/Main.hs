newtype Char = C Bool deriving Show
x :: Char
x = C True
main = print x
