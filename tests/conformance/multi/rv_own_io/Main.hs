data IO a = IOx a
y :: IO Bool
y = IOx True
main = putStrLn "hi"
