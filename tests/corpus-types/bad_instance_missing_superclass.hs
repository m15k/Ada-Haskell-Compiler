-- Report 4.3.2: an instance needs instances of its class's
-- superclasses at the same type. AHC built the Ord T dictionary with
-- a missing Eq superclass and died "$dMISSING" at run time (M142
-- review); both compilers now reject.
data T = T Int

instance Ord T where
  compare (T a) (T b) = compare a b

f :: Ord a => a -> a -> Bool
f x y = x == y

main :: IO ()
main = print (f (T 1) (T 2))
