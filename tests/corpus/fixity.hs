module F where
a = 1 + 2 * 3
b = 2 ^ 3 ^ 2
c = 1 : 2 : []
d = f . g . h $ x
  where f = id; g = id; h = id; x = 0
e y = -y * 2
infixr 7 <+>
(<+>) :: Int -> Int -> Int
a' <+> b' = a'
h' = 1 <+> 2 <+> 3
