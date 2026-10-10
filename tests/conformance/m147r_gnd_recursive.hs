newtype L = L [L] deriving (Eq, Ord)
newtype M a = M (Maybe (M a)) deriving (Eq)
main :: IO ()
main = do
  print (L [L []] == L [L []], L [] < L [L []])
  print (M (Just (M Nothing)) == (M Nothing :: M Int))
