instance Show (Maybe Int) where show _ = "mine"
g :: Show a => a -> String
g x = show (Just x)
main :: IO ()
main = putStrLn (g (1::Int))
