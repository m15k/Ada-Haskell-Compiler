module Data.Functor (fmap, (<$>), (<$), ($>)) where

infixl 4 <$>
infixl 4 <$
infixl 1 $>

(<$>) :: Functor f => (a -> b) -> f a -> f b
(<$>) f x = fmap f x

(<$) :: Functor f => a -> f b -> f a
(<$) x fb = fmap (\_ -> x) fb

($>) :: Functor f => f a -> b -> f b
($>) fa x = fmap (\_ -> x) fa
