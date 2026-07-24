-- Non-nullary deriving Enum: both compilers reject at compile time.
data T = A Int | B deriving (Eq, Show, Enum)

main :: IO ()
main = print B
