{-# LANGUAGE GeneralizedNewtypeDeriving #-}
-- M150 review: a newtype deriving Eq/Ord through a representation that
-- reaches the newtype itself. The structural-dictionary test reads the
-- newtype's own ==/compare while its dictionary is being built; it
-- must see a cycle (structural), not <<loop>>, in either method order,
-- and a polymorphically recursive newtype must terminate too.
newtype L = L [L] deriving (Eq, Ord, Show)
newtype M a = M (Maybe (M a)) deriving (Eq, Ord, Show)
newtype R = R (Maybe (Int, R)) deriving (Eq, Ord, Show)

main :: IO ()
main = do
  print (L [] < L [L []])
  print (compare (L [L []]) (L []), L [L []] == L [L []])
  print (M Nothing < M (Just (M Nothing)) :: Bool)
  print (compare (M (Just (M Nothing))) (M Nothing :: M Int))
  print (R (Just (1, R Nothing)) > R (Just (0, R (Just (5, R Nothing)))))
  print (maximum [L [], L [L [], L []], L [L []]])
  print ([L [L []], L []] == [L [L []], L []], Just (M Nothing :: M Char) < Nothing)
