module Shapes (Shape(..), area, module Util) where
import Util
data Shape = Sq Int | Rect Int Int deriving Show
area :: Shape -> Int
area (Sq n) = double n * n `div` 2
area (Rect w h) = w * h
