-- Report 4.1.2: (,) and (,,) are type constructors, prefix and
-- partially applied (M150).
newtype Wrap f a = Wrap (f a)

pairT :: (,) Int Bool
pairT = (1, True)

tripleT :: (,,) Int Char Bool
tripleT = (1, 'x', False)

wrapped :: Wrap ((,) String) Int
wrapped = Wrap ("k", 2)

main :: IO ()
main = print (pairT, tripleT)
