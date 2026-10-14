import Control.Exception
import Data.Char (chr)

t :: a -> IO ()
t x = (evaluate x >> putStrLn "ok") `catch` \e -> print (show (e :: SomeException))

main :: IO ()
main = do
  t (chr (-1))
  t (sum (map error ["a"]) :: Int)
  t (error . show $ (5 :: Int) :: ())
  t (flip (!!) 9 [1 :: Int])
  t (zipWith (!!) [[1::Int]] [3])
  t (fmap head (Just ([] :: [Int])))
  t (uncurry (!!) ([1::Int], 7))
  t (fst (head [], ()) :: Int)
  t ((head :: [Int] -> Int) [])
  t (head
       ([] :: [Int]))
  t (   undefined   :: Int)
  t ((undefined :: Int -> Int) 3)
  t (([] :: [Int]) !!
       3)
  t (id $! head [] :: Int)
  t (let xs = [] :: [Int] in xs !! 0 + 1)
  t ([] `seq` read "" :: Int)
  t (read "  12 x" :: Int)
