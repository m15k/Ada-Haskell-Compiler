-- M150 D2: a phantom parameter needs no instance (GHC infers an
-- empty context), so comparing and showing at a function type
-- compiles.
data Ph a = Ph Int deriving (Eq, Ord, Show)

main :: IO ()
main = print (Ph 1 == (Ph 1 :: Ph (Int -> Int)), Ph 2 :: Ph (IO ()))
