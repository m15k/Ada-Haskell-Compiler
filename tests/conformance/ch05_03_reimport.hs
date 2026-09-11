-- Report 5.2/5.3: a module may RE-export what it imported, an
-- export of C(..) carries the class's selectors whether or not the
-- class is the module's own, and a module imported twice is in
-- scope through every one of those imports.
module Main where

import Data.List as List
import Control.Applicative ((<$>), (<*>), pure)
import Prelude hiding (String)
import qualified Prelude (String)

-- A qualified type name through the SECOND import of Prelude; the
-- first one hides the very name the second brings.
label :: Prelude.String
label = "pair"

data Boxed = Boxed Prelude.String Int deriving Show

main :: IO ()
main = do
  -- Data.List carries the Prelude's list API, qualified.
  print (List.null ([] :: [Int]), List.length [1, 2, 3 :: Int])
  print (List.map (* 2) [1, 2, 3 :: Int])
  print (List.sum [1 .. 10 :: Int], List.maximum [3, 1, 2 :: Int])
  print (List.take 3 (List.cycle [1, 2 :: Int]))
  print (List.words "a b c", List.filter even [1 .. 6 :: Int])
  -- Control.Applicative's (<*>) and pure, imported by name off a
  -- class Control.Applicative does not itself declare.
  print ((,) <$> Just label <*> pure (3 :: Int))
  print (Boxed label 3)
