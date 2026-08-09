-- Report 4.2.3: a newtype constructor pattern is irrefutable at the
-- wrapper -- matching N p never forces the wrapper; only the
-- sub-pattern's own demand does. A data pattern of the same shape
-- forces (contrast pinned by GHC's identical output).
newtype N = N Int

data D = D Int

fN :: N -> Int
fN (N _) = 1

gD :: D -> Int
gD (D _) = 2

-- Refutable sub-pattern under the newtype: decided by the coerced
-- value, so the projection is demanded, not the wrapper.
newtype M = M (Maybe Int)

h :: M -> Int
h (M (Just x)) = x
h (M Nothing) = 0

-- Nullary type synonym for a partially applied constructor,
-- applied further (Report 4.2.2 requires only the synonym itself
-- to be saturated).
type E = Either String

k :: E Int -> E Int
k = fmap (+ 1)

main :: IO ()
main = do
  print (fN undefined)
  print (gD (D undefined))
  print (h (M (Just 9)))
  print (h (M Nothing))
  print (k (Right 4))
  print (k (Left "no"))
  print (fmap not (Right False :: Either Int Bool))
  print (Right 3 >>= (\x -> Right (x + 1)) :: Either String Int)
  print ((Left "e" :: Either String Int) >>= (\x -> Right (x + 1)))
  print (pure 7 :: Either String Int)
