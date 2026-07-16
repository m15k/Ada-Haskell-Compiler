-- Report 4.3.1-4.3.2: class declarations with defaults, instance
-- declarations overriding them, superclass constraints in use.
class Describable a where
  score :: a -> Int
  bonus :: a -> Int
  bonus x = score x * 2

data Cat = Cat
data Dog = Dog

instance Describable Cat where
  score _ = 10

instance Describable Dog where
  score _ = 1
  bonus _ = 99

best :: (Describable a, Describable b) => a -> b -> Int
best x y = max (bonus x) (bonus y)

main :: IO ()
main = do
  print (score Cat, bonus Cat)
  print (score Dog, bonus Dog)
  print (best Cat Dog)
