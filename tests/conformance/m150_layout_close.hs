{-# LANGUAGE LambdaCase #-}
-- M150: a token that cannot start an item closes an implicit layout
-- block (Report 10.3's parse-error(t)), in case, \cases, let and
-- where blocks as it already did in do blocks.

pairCase :: Int -> (Int, Int)
pairCase n = (case n of
  1 -> 1
  _ -> 2
  , 2)

parenCase :: Int -> Int
parenCase n = (case n of
  0 -> 10
  _ -> 20
  )

listCase :: Int -> [Int]
listCase n = [case n of
  0 -> 1
  _ -> 2
  ]

pick :: Int -> Int -> Int
pick = (\cases
  0 y -> y
  x _ -> x
  )

compLet :: [Int]
compLet = [ x + y | let x = 5
                        y = 6
                        , True ]

whereComma :: Int -> (Int, Int)
whereComma n = (case n of
  m -> j
    where
    j = m * 3
    , 1)

-- Already accepted before M150: `in` at the bindings' column.
letIn :: Int
letIn = let a = 1
            b = 2
            in a + b

main :: IO ()
main = do
  print (pairCase 1)
  print (parenCase 0, parenCase 5)
  print (listCase 3)
  print (pick 0 7, pick 3 7)
  print compLet
  print (whereComma 2)
  print letIn
