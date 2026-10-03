module Main where
import qualified Mid as M
import qualified L
import qualified R
data Box = Box S R.S deriving Show
type S = Bool
y :: M.P
y = M.mk2 4
z :: L.P
z = (1, 2)
main :: IO ()
main = do
  print y
  print z
  print (Box True [7])
