{-# LANGUAGE LambdaCase #-}
main :: IO ()
main = do
  let f = \cases
        a b -> a - b :: Int
        `seq` (7 :: Int)
  print f
  let g = \case
        a -> a :: Int
        `seq` (8 :: Int)
  print g
