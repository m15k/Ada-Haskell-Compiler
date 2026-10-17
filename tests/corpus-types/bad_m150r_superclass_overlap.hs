{-# LANGUAGE FlexibleInstances #-}
newtype P a = P a
instance Eq (P a) where _ == _ = True
instance Eq (P Int) where _ == _ = False
instance Ord (P Int) where compare _ _ = EQ
main = print 1
