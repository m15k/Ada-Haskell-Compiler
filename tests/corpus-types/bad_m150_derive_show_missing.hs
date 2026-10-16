-- M150 D2: a derived Show whose field has no Show instance is a
-- compile error in both compilers (GHC: No instance for (Show F)).
data F = F

data T = T Int F deriving Show

main :: IO ()
main = print (T 1 F)
