-- Report 4.2.3: a newtype adds no run-time box (M147).
import Control.Exception

newtype N = N Int deriving (Show, Eq, Ord)
newtype R = R { unR :: [Int] } deriving (Show, Read)
data D = D N String deriving (Show, Eq)
newtype F = F (Int -> Int)

probe :: a -> IO ()
probe x = do
  r <- try (evaluate x)
  putStrLn (either (\e -> "bottom: " ++ takeWhile (/= '\n') (show (e :: ErrorCall))) (const "value") r)

apply :: F -> Int -> Int
apply (F f) = f

main :: IO ()
main = do
  probe (N undefined `seq` ())
  probe (case (undefined :: N) of N _ -> ())
  probe (let N _ = undefined in ())
  probe (R undefined `seq` ())
  probe (F undefined `seq` ())
  print (N 3, unR (R [1, 2]), (R [3]) { unR = [4] }, read "R {unR = [5]}" :: R)
  print (D (N 1) "a" == D (N 1) "a", compare (N 2) (N 3), map unR [R [], R [0]])
  print (showsPrec 11 (N (-4)) "", show (Just (N 7)), apply (F (* 2)) 21)
