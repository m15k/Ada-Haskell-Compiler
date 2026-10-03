module Right (Pair, Named (..), R (..), describe) where
type Pair = (Bool, Bool)
class Named a where
  name :: a -> String
data R = R
instance Named R where
  name _ = "right"
describe :: Pair -> String
describe (a, b) = "R" ++ show (a && b)
