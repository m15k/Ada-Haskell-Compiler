data Box a = Box a
instance Foldable Box where
  foldMap f (Box a) = f a
main = print (sum (Box (3 :: Int)))
