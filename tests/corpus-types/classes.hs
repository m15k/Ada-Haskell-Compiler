data Color = Red | Green deriving (Eq, Show)
class Pretty a where
  pretty :: a -> String
instance Pretty Color where
  pretty Red = "red"
  pretty Green = "green"
describe c = pretty c ++ "!"
check1 = Red == Green
main = putStrLn (describe Red)
