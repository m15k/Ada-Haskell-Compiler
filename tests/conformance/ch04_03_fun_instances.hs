-- Instances over the function type (M142): a type-constructor
-- variable applied to two arguments unifies with `a -> b`, so
-- `instance C (->)`, `instance C ((->) r)` and `instance C (a -> r)`
-- resolve - the shape Text.Printf is built on.
class Cat k where
  idC  :: k a a
  comp :: k b c -> k a b -> k a c

instance Cat (->) where
  idC = \x -> x
  comp f g = \x -> f (g x)

class Cat k => Arr k where
  arr :: (a -> b) -> k a b

instance Arr (->) where
  arr f = f

class Fn f where
  fmapF :: (a -> b) -> f a -> f b

instance Fn ((->) r) where
  fmapF = (.)

newtype Out = Out [String]

class Collect r where
  collect :: [String] -> r

instance Collect Out where
  collect = Out . reverse

instance (Show a, Collect r) => Collect (a -> r) where
  collect acc = \a -> collect (show a : acc)

run :: Out -> [String]
run (Out xs) = xs

twice :: Arr k => k Int Int
twice = arr (* 2)

main :: IO ()
main = do
  print (idC (5 :: Int))
  print (comp (+ 1) (* 2) (10 :: Int))
  print (arr show (comp idC (+ 1) (41 :: Int)))
  print (fmapF (* 3) (+ 1) (4 :: Int))
  print (run (collect [] (1 :: Int) True 'x'))
  print (twice 21)
