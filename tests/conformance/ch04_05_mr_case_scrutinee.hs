-- A case whose scrutinee is a class method's result, with the class
-- variable fixed only through a binder in one alternative (the
-- shape of Control.Exception's catch). The desugarer binds the
-- scrutinee in a let; that let must be MONOMORPHIC, or every
-- binder-free alternative instantiates a fresh, ambiguous copy of
-- the constraint (M138).
class Unwrap f where
  unwrap :: Int -> Maybe f

instance Unwrap Bool where
  unwrap n = if n == 0 then Nothing else Just (n > 0)

instance Unwrap Char where
  unwrap n = if n < 0 then Nothing else Just (toEnum (65 + n))

pick :: Unwrap f => Int -> (f -> String) -> String
pick n k = case unwrap n of
             Just x -> k x
             Nothing -> "nothing"

describe :: Int -> String
describe n = case unwrap n of
               Just c -> [c, c]
               Nothing -> "-"

main :: IO ()
main = do
  putStrLn (pick 3 (\b -> show (b :: Bool)))
  putStrLn (pick 0 (\b -> show (b :: Bool)))
  putStrLn (pick 2 (\c -> [c :: Char]))
  putStrLn (describe 1)
  putStrLn (describe (-1))
  -- an explicit let, the same shape (the monomorphism restriction)
  let s = unwrap 5
  putStrLn (case s of
              Just b -> if b then "yes" else "no"
              Nothing -> "none")
