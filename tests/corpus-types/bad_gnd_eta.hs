{-# LANGUAGE GeneralizedNewtypeDeriving #-}
-- GHC 9.4.8: Can't make a derived instance of 'Functor C'
-- (even with cunning GeneralizedNewtypeDeriving) - a contravariant
-- field. AHC: the representation does not end in its last type
-- variable (AHC has no stock DeriveFunctor; see EXCLUSIONS).
newtype C a = C (a -> Int) deriving (Functor)
main :: IO ()
main = return ()
