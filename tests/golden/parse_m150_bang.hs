module M where
f !x (!a, b) (Just !y) = x
g = \ !z ~(!w) -> z
h xs = let !n = length xs in n
xs ! i = i
k arr = arr!0
data T = T !Int ! Int
