{-# LANGUAGE FlexibleInstances, TypeSynonymInstances #-}
-- FlexibleInstances/TypeSynonymInstances, always on in AHC (M147).
class Pretty a where
  pretty :: a -> String

instance Pretty String where
  pretty s = "str:" ++ s
instance Pretty (Maybe Int) where
  pretty m = "maybe-int:" ++ show m
instance Pretty (Maybe Bool) where
  pretty m = "maybe-bool:" ++ show m
instance Pretty (Either String Int) where
  pretty = either ("left:" ++) (("right:" ++) . show)
instance Show a => Pretty [Maybe a] where
  pretty xs = "maybes:" ++ show xs

class Describe a where
  describe :: a -> String
instance Describe [Char] where
  describe _ = "a string"
instance Describe [a] where
  describe xs = "a list of " ++ show (length xs)

class Shout a where
  shout :: a -> String
instance Shout a where
  shout _ = "!"

type Name = String
greet :: Name -> String
greet n = pretty n

loud :: a -> String
loud x = shout x ++ shout x

main :: IO ()
main = do
  putStrLn (pretty "hi")
  putStrLn (pretty (Just (3 :: Int)))
  putStrLn (pretty (Just True))
  putStrLn (pretty (Left "e" :: Either String Int))
  putStrLn (pretty (Right 7 :: Either String Int))
  putStrLn (pretty [Just 'x', Nothing])
  putStrLn (describe [True, False])
  putStrLn (shout (1 :: Int) ++ shout "s" ++ loud ())
  putStrLn (greet "ada")
