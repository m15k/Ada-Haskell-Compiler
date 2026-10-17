import Control.Applicative (liftA2)
-- an Applicative whose effects record which method ran
newtype L a = L ([String], a)
instance Functor L where fmap f (L (w, a)) = L (w ++ ["fmap"], f a)
instance Applicative L where
  pure a = L (["pure"], a)
  L (w1, f) <*> L (w2, a) = L (w1 ++ w2 ++ ["ap"], f a)
  liftA2 f (L (w1, a)) (L (w2, b)) = L (w1 ++ w2 ++ ["liftA2"], f a b)
logs (L (w, _)) = w
main = do
  print (logs (traverse (\x -> L ([show x], x)) [1,2]))
  print (logs (sequenceA [L (["a"], 1)]))
  print (logs (traverse (\x -> L ([show x], x)) (Just 1)))
  print (logs (traverse (\x -> L ([show x], x)) (Right 1 :: Either () Int)))
  print (logs (traverse (\x -> L ([show x], x)) ((), 1)))
  print (logs (L (["x"], 1) *> L (["y"], 2)))
  print (logs (L (["x"], 1) <* L (["y"], 2)))
