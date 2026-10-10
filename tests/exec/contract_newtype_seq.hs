-- Contract discharge must not fold `N e `seq` True` to True: newtypes
-- are erased (M147), so N applied to bottom is bottom and the
-- precondition is kept and fires at run time (M147 review).
newtype N = N Int

{-# PRE f \x -> N (error "pre of f is bottom") `seq` True #-}
f :: Int -> Int
f x = x + 1

{-# PRE g \x -> x == x && (N (error "pre of g is bottom") `seq` True) #-}
g :: Int -> Int
g x = x + 1

main :: IO ()
main = do
  print (f 1)
  print (g 1)
