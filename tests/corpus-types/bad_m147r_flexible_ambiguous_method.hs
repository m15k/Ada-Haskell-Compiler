class C a where c :: a -> String
instance C (Maybe Int) where c _ = "mi"
data T = T
instance Show T where show _ = c Nothing
main :: IO ()
main = print T
