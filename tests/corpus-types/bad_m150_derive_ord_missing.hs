-- M150 D2: a derived Ord over a field that has Eq but no Ord.
data F = F deriving Eq

data W a = W a F deriving (Eq, Ord)

main :: IO ()
main = print (W 'x' F == W 'x' F)
