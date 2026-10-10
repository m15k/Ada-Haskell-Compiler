module A (P(..), mkDefault) where
data P = P { px :: Int, py :: Int } deriving Show
mkDefault :: P
mkDefault = P 1 2
