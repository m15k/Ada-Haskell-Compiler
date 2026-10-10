{-# LANGUAGE DeriveFunctor #-}
-- GHC 9.4.8: Constructor must not use the type variable in a function argument
data Contra a = Contra (a -> Int) deriving Functor
main :: IO ()
main = return ()
