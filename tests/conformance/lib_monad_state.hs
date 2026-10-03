-- Control.Monad.State (M142): State and StateT used directly, as most
-- real programs do; mtl's MonadState class is not in Haskell 2010.
import Control.Monad.State
import Data.Functor.Identity

counter :: State Int Int
counter = do
  modify (+ 1)
  x <- get
  put (x * 10)
  gets (* 2)

push :: Int -> State [Int] ()
push x = modify (x :)

pop :: State [Int] (Maybe Int)
pop = do
  s <- get
  case s of
    []       -> return Nothing
    (x : xs) -> put xs >> return (Just x)

labels :: [String] -> State Int [(Int, String)]
labels = mapM (\w -> do n <- get; put (n + 1); return (n, w))

loop :: StateT Int IO ()
loop = do
  n <- get
  when (n < 3) $ do
    liftIO (putStrLn ("tick " ++ show n))
    put (n + 1)
    loop

main :: IO ()
main = do
  print (runState counter 4)
  print (evalState (mapM_ push [1, 2, 3] >> replicateM 4 pop) [])
  print (evalState (labels (words "a b c")) 100)
  print (execState (forM_ [1 .. 10] (\i -> modify' (+ i))) 0)
  print (runState (state (\s -> (s * 2, s + 1)) >>= \a -> gets (+ a)) 5)
  print (evalState (withState (* 3) get) 7, runState (mapState (\(a, s) -> (show a, s)) get) 'x')
  s <- execStateT loop 0
  print s
  r <- evalStateT (do { lift (putStrLn "lifted"); gets length }) "abc"
  print r
  print (Identity (3 :: Int), runIdentity (fmap (+ 1) (Identity 1)))
