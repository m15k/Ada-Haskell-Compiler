module Data.Bool (bool, (&&), (||), not, otherwise) where

bool :: a -> a -> Bool -> a
bool f _ False = f
bool _ t True  = t
