module Main where

import Geometry
import qualified Util
import Util (double)

main :: IO ()
main = do
  print (area (Circle 1))
  print (area unitSquare)
  print unitSquare
  print (double 21)
  print (Util.area 5)
  print (Util.double 7)
