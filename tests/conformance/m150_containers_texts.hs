-- M150: the show of a caught Data.Map / Data.Set error is GHC
-- 9.4.8's, byte for byte, with containers-0.6.7's call stack (its
-- functions are not HasCallStack, so no frame is the program's).
import Control.Exception
import qualified Data.Map as Map
import qualified Data.Map.Strict as MapS
import qualified Data.Set as Set

t :: String -> IO () -> IO ()
t name act = do
  r <- try act
  case r of
    Left e -> putStrLn (name ++ " => " ++ show (e :: SomeException))
    Right () -> putStrLn (name ++ " ok")

f :: a -> IO ()
f x = evaluate x >> return ()

em :: Map.Map Int Char
em = Map.empty

m :: Map.Map Int Char
m = Map.fromList [(1, 'a'), (2, 'b')]

es :: Set.Set Int
es = Set.empty

s :: Set.Set Int
s = Set.fromList [1, 2, 3]

main :: IO ()
main = do
  t "Map.!" (f (m Map.! 5))
  t "Map.Strict.!" (f (m MapS.! 5))
  t "Map.findIndex" (f (Map.findIndex 5 m))
  t "Map.elemAt" (f (Map.elemAt 7 m))
  t "Map.elemAt negative" (f (Map.elemAt (-1) m))
  t "Map.deleteAt" (f (Map.deleteAt 7 m))
  t "Map.findMin" (f (Map.findMin em))
  t "Map.findMax" (f (Map.findMax em))
  t "Map.deleteFindMin" (f (fst (Map.deleteFindMin em)))
  t "Map.deleteFindMax" (f (fst (Map.deleteFindMax em)))
  t "Map maximum" (f (maximum em))
  t "Map minimum" (f (minimum em))
  t "Map foldr1" (f (foldr1 max em))
  t "Set.elemAt" (f (Set.elemAt 7 s))
  t "Set.findIndex" (f (Set.findIndex 9 s))
  t "Set.findMin" (f (Set.findMin es))
  t "Set.findMax" (f (Set.findMax es))
  t "Set maximum" (f (maximum es))
  t "Set minimum" (f (minimum es))
  t "Set foldr1" (f (foldr1 max es))
  -- the values the same functions return when they succeed
  print (m Map.! 2, Map.elemAt 1 m, Map.findMin m, Map.findMax m)
  print (Map.findIndex 2 m, Map.deleteAt 0 m, fst (Map.deleteFindMax m))
  print (maximum m, minimum m)
  print (Set.findMin s, Set.findMax s, maximum s, minimum s)
  print (Set.findMin (Set.fromList "hello"), Set.findMax (Set.fromList "hello"))
  print (Set.elemAt 2 s, Set.findIndex 3 s)
