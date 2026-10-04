module Main where
import Shapes
import qualified Util as U
main :: IO ()
main = print (area (Sq 3), U.double 4, label Red)
