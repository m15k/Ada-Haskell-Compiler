{-# LANGUAGE FlexibleContexts #-}
-- FlexibleContexts (M148): constraints over constructed types in
-- signatures, always on in AHC.
import qualified Data.Map as M
class Pretty a where pretty :: a -> String
instance Pretty Int where pretty n = "#" ++ show n
instance Pretty a => Pretty [a] where pretty = concatMap pretty
showAll :: (Show (f Int), Functor f) => f Int -> String
showAll x = show (fmap (+1) x)
prettyList :: Pretty [a] => [a] -> String
prettyList = pretty
lookupShow :: (Ord k, Show (M.Map k v)) => M.Map k v -> String
lookupShow = show
main :: IO ()
main = do
  putStrLn (showAll (Just 1))
  putStrLn (showAll [1, 2])
  putStrLn (prettyList [1, 2 :: Int])
  putStrLn (lookupShow (M.fromList [(1 :: Int, "a")]))
