type Nat = Int satisfying (\n -> n >= 0)

f :: Nat in 0 .. 5
f = 1

g :: Maybe satisfying even
g = Nothing
