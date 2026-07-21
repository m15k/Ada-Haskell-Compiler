-- Class constraints arising inside where-helpers must discharge
-- against the enclosing signature's context - including from inside
-- match-compiler join points (multi-equation helpers) and through
-- superclasses. Pins the floated-wanted Owner bug found while
-- porting the mini-Lisp interpreter to Data.Map (M59).
memb :: Ord k => k -> [(k, a)] -> Bool
memb _ [] = False
memb k ((kx, _) : rest) = if k == kx then True else memb k rest

ins :: Ord k => k -> a -> [(k, a)] -> [(k, a)]
ins k x ps = (k, x) : ps

-- Multi-equation where-helper calling Ord-schemed functions: the
-- helper's own wanteds must join its inferred local context.
uni :: Ord k => [(k, a)] -> [(k, a)] -> [(k, a)]
uni m1 m2 = goU m1 m2
  where
    goU m [] = m
    goU m ((k, x) : rest) =
      if memb k m then goU m rest else goU (ins k x m) rest

-- Sibling where-helpers over the OUTER tyvar: the Eq wanted must
-- reach the signature's Ord given through the superclass.
g :: Ord k => [k] -> [k] -> [k]
g ks m = goG m ks
  where
    goG acc [] = acc
    goG acc (k : rest) =
      if elem2 k acc then goG acc rest else goG (k : acc) rest
    elem2 _ [] = False
    elem2 x (y : ys) = if x == y then True else elem2 x ys

main :: IO ()
main = do
  print (uni [(1 :: Integer, "a")] [(1, "b"), (2, "c")])
  print (g [1 :: Integer, 2] [2, 3])
