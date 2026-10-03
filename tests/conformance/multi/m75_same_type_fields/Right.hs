module Right where
data T = A Int | B { fld :: Int } deriving (Show, Eq, Ord)
data E = X | Y | Z deriving (Show, Eq, Ord, Enum, Bounded)
newtype N = N Int deriving (Show, Eq)
class C a where
  c :: a -> String
instance C T where
  c t = "Right:" ++ show t
instance C E where
  c e = "Right-E:" ++ show [minBound .. e]
type P = (T, E)
mk :: Int -> P
mk n = (B { fld = n }, maxBound)
upd :: T -> T
upd t = t { fld = 99 }
