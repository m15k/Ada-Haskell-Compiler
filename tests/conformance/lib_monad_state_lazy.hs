-- Control.Monad.State is mtl's LAZY StateT; .Strict is a distinct,
-- strict one (the M142 review round).
import Control.Monad.State
import qualified Control.Monad.State.Strict as S
import Control.Exception

main :: IO ()
main = do
  -- an infinite mapM produces its list lazily
  print (take 5 (evalState (mapM (\x -> state (\s -> (x + s, s + 1))) [1 ..]) (0 :: Int)))
  -- a bottom state pair is never demanded when the result is not
  print (evalState (state (\_ -> undefined) >> return 'x') (0 :: Int))
  print (fst (runState (fmap (+ 1) (return 1 >> state (\s -> (s, undefined)))) (41 :: Int)))
  print (evalState (pure (,) <*> return 'a' <*> state (\_ -> undefined)) () `seq` "applicative ok")
  -- a lazy knot: the final state feeds an earlier result
  let (xs, n) = runState (mapM (\c -> do { k <- get; put (k + 1); return (c, k) }) "abc") (0 :: Int)
  print (xs, n)
  print (execState (forM_ [1 .. 10 :: Int] (\i -> modify (+ i))) 0)
  r <- execStateT (mapM_ (\i -> modify' (+ i)) [1 .. 1000 :: Int]) 0
  print r
  print (evalState (withState (* 2) get) (21 :: Int))
  print (runState (mapState (\(a, s) -> (show a, s + 1)) (gets (* 3))) (5 :: Int))
  print =<< evalStateT (mapStateT (fmap (\(a, s) -> (a * 2, s))) get) (8 :: Int)
  print =<< runStateT (withStateT (+ 1) get) (1 :: Int)
  -- the strict module forces the pair at every bind
  e <- try (evaluate (S.evalState (S.state (\_ -> undefined) >> return 'x') (0 :: Int)))
  putStrLn (either (\err -> "strict: " ++ takeWhile (/= '\n') (show (err :: ErrorCall))) show e)
  print (S.evalState (S.state (\s -> (s, undefined)) >> return 'y') (0 :: Int))
  print (S.runState (do { S.modify (+ 1); x <- S.get; S.put (x * 10); S.gets (* 2) }) (1 :: Int))
  print (S.execState (S.withState (+ 1) (S.modify' (* 2))) (3 :: Int))
  r2 <- S.execStateT (mapM_ (\i -> S.modify' (+ i)) [1 .. 1000 :: Int]) 0
  print r2
