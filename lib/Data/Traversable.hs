module Data.Traversable
  ( Traversable (..)
  , for, forM
  , mapAccumL, mapAccumR
  ) where

--  GHC 9.4.8's Data.Traversable, minus fmapDefault/foldMapDefault.
--  The class itself is the Prelude's (base's shape since M150, with
--  mapM and sequence as methods).

for :: (Traversable t, Applicative f) => t a -> (a -> f b) -> f (t b)
for t f = traverse f t

forM :: (Traversable t, Monad m) => t a -> (a -> m b) -> m (t b)
forM t f = mapM f t

--  State threaded left to right (base's StateL) ...
newtype StateL_ s a = StateL_ (s -> (s, a))

runStateL_ :: StateL_ s a -> s -> (s, a)
runStateL_ (StateL_ k) = k

instance Functor (StateL_ s) where
  fmap f (StateL_ k) = StateL_ (\s -> let (s', v) = k s in (s', f v))

instance Applicative (StateL_ s) where
  pure x = StateL_ (\s -> (s, x))
  StateL_ kf <*> StateL_ kv =
    StateL_ (\s -> let (s', f) = kf s
                       (s'', v) = kv s'
                   in (s'', f v))

--  ... and right to left (base's StateR).
newtype StateR_ s a = StateR_ (s -> (s, a))

runStateR_ :: StateR_ s a -> s -> (s, a)
runStateR_ (StateR_ k) = k

instance Functor (StateR_ s) where
  fmap f (StateR_ k) = StateR_ (\s -> let (s', v) = k s in (s', f v))

instance Applicative (StateR_ s) where
  pure x = StateR_ (\s -> (s, x))
  StateR_ kf <*> StateR_ kv =
    StateR_ (\s -> let (s', v) = kv s
                       (s'', f) = kf s'
                   in (s'', f v))

mapAccumL :: Traversable t => (s -> a -> (s, b)) -> s -> t a -> (s, t b)
mapAccumL f s t = runStateL_ (traverse (\a -> StateL_ (\s' -> f s' a)) t) s

mapAccumR :: Traversable t => (s -> a -> (s, b)) -> s -> t a -> (s, t b)
mapAccumR f s t = runStateR_ (traverse (\a -> StateR_ (\s' -> f s' a)) t) s
