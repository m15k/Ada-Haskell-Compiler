-- Traversable's traverse and sequenceA (base-compat, like Applicative
-- and Semigroup): two JSON parsers off GitHub used them with no
-- import at all, since GHC's Prelude exports them (M141).
main :: IO ()
main = do
  print (traverse (\x -> if x > 0 then Just x else Nothing) [1, 2, 3 :: Int])
  print (traverse (\x -> if x > 0 then Just x else Nothing) [1, -2, 3 :: Int])
  print (sequenceA [Just 1, Just (2 :: Int)], sequenceA [Just 1, Nothing :: Maybe Int])
  print (traverse (\c -> [c, c]) ['a', 'b'])
  print (sequenceA (Just [1, 2 :: Int]))
  print (traverse (\x -> if even x then Right x else Left (show x)) [2, 4 :: Int])
  print (traverse (\x -> if even x then Right x else Left (show x)) [2, 5 :: Int])
  print (sequenceA (Right (Just 'x') :: Either String (Maybe Char)))
  print (traverse Just (Nothing :: Maybe Int), traverse Just (Just (1 :: Int)))
