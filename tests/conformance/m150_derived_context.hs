-- M150 D2: derived Eq/Ord/Show/Read contexts are inferred from the
-- constructor fields, as GHC infers them.

data Ph a = Ph Int deriving (Eq, Ord, Show, Read)

data Wrap a = Wrap [a] (Maybe a) deriving (Eq, Ord, Show)

data L a = N | C a (L a) deriving (Eq, Ord, Show)

data Even a = EZ | ES a (Odd a) deriving (Eq, Show)
data Odd a = OS a (Even a) deriving (Eq, Show)

data Two a b = Two b deriving (Eq, Show)

main :: IO ()
main = do
  print (Ph 1 == (Ph 1 :: Ph (Int -> Int)))
  print (compare (Ph 2) (Ph 1 :: Ph (IO ())), Ph 3 < (Ph 4 :: Ph (Int -> Int)))
  print (Ph 5 :: Ph (Int -> Bool))
  print (read "Ph 7" == (Ph 7 :: Ph (Bool -> Bool)))
  print (Wrap [1, 2] (Just 3) == Wrap [1, 2] (Just (3 :: Int)))
  print (Wrap "ab" Nothing < Wrap "ac" Nothing)
  print (C 1 (C 2 N) == C 1 (C (2 :: Int) N), compare (C 'a' N) (C 'a' (C 'b' N)))
  print (ES 'x' (OS 'y' EZ) == ES 'x' (OS 'y' EZ))
  print (Two 'k' == (Two 'k' :: Two (Int -> Int) Char))
  print (Two True :: Two (IO ()) Bool)
