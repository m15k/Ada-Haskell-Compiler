newtype Wrap f a = Wrap (f a) deriving (Eq)
main :: IO ()
main = print (Wrap (Just 1) == Wrap (Just 1))
