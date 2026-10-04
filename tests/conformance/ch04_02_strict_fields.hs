-- Strict fields (Report 4.2.1): a constructor applied to its
-- arguments forces each `!` field, so `T undefined` is bottom; lazy
-- fields and newtypes are unaffected (M142 review: AHC parsed the
-- annotations and ignored them).
import Control.Exception

data T = T !Int

data P = P !Int Int

data R = R { rx :: !Int, ry :: Int }

data L = L Int

newtype N = N Int  -- (seq on a newtype: see EXCLUSIONS 4.2.3)

data Pair a = Pair !a !a deriving Show

isBottom :: a -> IO String
isBottom x = do
  r <- try (evaluate x)
  return (case r of
            Left e -> "bottom: " ++ takeWhile (/= '\n') (show (e :: ErrorCall))
            Right _ -> "value")

main :: IO ()
main = do
  isBottom (T undefined) >>= putStrLn
  isBottom (T 3) >>= putStrLn
  isBottom (P 1 undefined) >>= putStrLn
  isBottom (P undefined 1) >>= putStrLn
  isBottom (R { rx = error "rx", ry = 2 }) >>= putStrLn
  isBottom (R { rx = 1, ry = error "ry" }) >>= putStrLn
  isBottom (L undefined) >>= putStrLn
  isBottom (case T (error "scrutinee") of T _ -> ()) >>= putStrLn
  isBottom (case L (error "lazy") of L _ -> ()) >>= putStrLn
  -- the constructor used as a function, partially applied
  let mk = Pair (1 :: Int)
  isBottom (mk (error "second")) >>= putStrLn
  isBottom (map (Pair 'a') "bc") >>= putStrLn
  isBottom (length (map T [1, undefined, 3])) >>= putStrLn
  isBottom (map T [1, undefined, 3] !! 1) >>= putStrLn
  let r = R { rx = 1, ry = 2 }
  isBottom (r { rx = error "update" }) >>= putStrLn
  print (Pair 'x' 'y', rx r, ry r)
