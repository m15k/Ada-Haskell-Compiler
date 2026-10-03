module Left (Pair, Named (..), L (..), describe) where
type Pair = (Int, Int)
class Named a where
  name :: a -> String
data L = L
instance Named L where
  name _ = "left"
describe :: Pair -> String
describe (a, b) = "L" ++ show (a + b)
