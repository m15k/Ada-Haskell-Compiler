module Inner (Widget (..), spin) where

data Widget = Widget Int deriving (Eq, Show)

spin :: Widget -> Widget
spin (Widget n) = Widget (n + 1)

secret :: Int
secret = 99
