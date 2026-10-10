newtype M a = M (Maybe a) deriving (Show, Monad)
main :: IO ()
main = print (M (Just 1) >>= \x -> return (x + 1))
