data F = F

data T = T Int F deriving Show

data U = U [F] | V deriving (Eq)

data R = R { g :: Int -> Int } deriving Eq

data W a = W a F deriving (Eq, Ord)

data Q = Q Int Bool (Maybe F) deriving (Read)

data K = K (IO ()) deriving (Show)

main :: IO ()
main = return ()
