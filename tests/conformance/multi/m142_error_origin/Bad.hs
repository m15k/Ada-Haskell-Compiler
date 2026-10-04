module Bad (render) where

-- The signature is too general: `show` needs Show a. The error is
-- judged in the typechecker's final residual sweep, after Main's
-- instance has moved the diagnostic origin on.
render :: a -> String
render x = show x
