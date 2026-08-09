module Data.Functor (fmap, (<$>), (<$), ($>)) where

--  fmap, (<$>) and (<$) are the Prelude's, re-exported; only ($>) is
--  this module's own (GHC's Prelude does not export it either).

infixl 1 $>

($>) :: Functor f => f a -> b -> f b
($>) fa x = fmap (\_ -> x) fa
