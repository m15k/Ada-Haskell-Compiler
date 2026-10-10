class P a where p :: a -> String
instance P Int where p n = "i" ++ show n
instance P a => P [a] where p xs = "[" ++ concatMap p xs ++ "]"
instance P a => P (Maybe a) where
  p Nothing = "N"
  p (Just x) = "J" ++ p x
newtype Y a = Y [Maybe a] deriving (P)
main :: IO ()
main = putStrLn (p (Y [Just (1 :: Int)]))
