module R where
import qualified L
type S = [L.S]
type P = (S, L.P)
mk :: Int -> P
mk n = ([n, n], (n, n+1))
