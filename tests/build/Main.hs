-- run_build.sh fixture: a multi-module program with a stdlib
-- import, built OUT OF TREE (from a directory that is not the
-- checkout) to pin AHC.Paths' installation-relative resolution.
module Main where

import Util (label)
import qualified Data.Map as M

main :: IO ()
main = do
  let m = M.fromList [(1 :: Int, "one"), (2, "two")]
  putStrLn (label ++ show (M.toList m))
