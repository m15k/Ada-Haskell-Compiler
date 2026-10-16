module Shapes (Shape (..), Size (..)) where

data Shape = Circle | Square deriving (Show, Enum)

data Size
  = Small
  | Large
  deriving (Show, Eq, Ord, Enum, Bounded)
