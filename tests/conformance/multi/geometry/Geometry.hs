module Geometry (Shape (..), area, unitSquare) where

data Shape = Circle Double | Rect Double Double deriving Show

area :: Shape -> Double
area (Circle r) = pi * r * r
area (Rect w h) = w * h

unitSquare :: Shape
unitSquare = Rect 1 1

hidden :: Int
hidden = 42
