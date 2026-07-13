module R where
data Person = Person { name :: String, age :: Int } deriving Show
birthday p = p { age = age p + 1 }
greet Person { name = n } = "hi " ++ n
mk = Person { name = "x", age = 0 }
