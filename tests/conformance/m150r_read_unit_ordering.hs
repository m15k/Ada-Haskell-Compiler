import qualified Data.Map as M
import qualified Data.Set as S
import Data.Array
type Name = String
type Env a = M.Map Name a
type F a = a -> a
data A a = A [a] (Maybe (a, Name)) (Env a) (S.Set a) deriving (Eq, Ord, Show)
newtype C = C (Env Int) deriving (Eq, Ord, Show)
data D a = D (Either a (A a)) deriving (Eq, Ord, Show)
data E = E (Int, Char) ((), Bool) Ordering deriving (Eq, Ord, Show, Read)
data G a b = G a | GG (G b a) deriving (Eq, Ord, Show)
main = do
  let a = A [1] (Just (2, "x")) (M.fromList [("k", 3)]) (S.fromList [4]) :: A Int
  print (a == a, compare a a, a < A [2] Nothing M.empty S.empty)
  print (C M.empty < C (M.fromList [("a",1)]), D (Left 'x') < D (Right (A [] Nothing M.empty S.empty)))
  print (read "E (1,'c') ((),True) GT" :: E)
  print (GG (G 'a') < (GG (GG (G 1)) :: G Int Char))
