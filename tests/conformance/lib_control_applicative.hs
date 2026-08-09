-- Control.Applicative: Alternative (empty/<|>/some/many), ZipList,
-- Const, WrappedMonad, optional/asum/liftA/liftA3/<**>, and the
-- operator fixities travelling across the import (<|> at infixl 3
-- against <$>/<*> at infixl 4).
import Control.Applicative

-- A newtype state parser: some/many must terminate through the
-- irrefutable newtype pattern (Report 4.2.3), as in base.
newtype P a = P { runP :: String -> Maybe (a, String) }

instance Functor P where
  fmap f (P p) = P (\s -> case p s of
    Nothing -> Nothing
    Just (a, r) -> Just (f a, r))

instance Applicative P where
  pure x = P (\s -> Just (x, s))
  P f <*> P p = P (\s -> case f s of
    Nothing -> Nothing
    Just (g, r) -> case p r of
      Nothing -> Nothing
      Just (a, r2) -> Just (g a, r2))

instance Alternative P where
  empty = P (\_ -> Nothing)
  P l <|> P r = P (\s -> case l s of
    Nothing -> r s
    ok -> ok)

item :: Char -> P Char
item c = P (\s -> case s of
  (x : xs) -> if x == c then Just (c, xs) else Nothing
  _ -> Nothing)

main :: IO ()
main = do
  print (Nothing <|> Just 2 <|> Just 9)
  print ([1, 2] <|> [3])
  print (empty :: [Int])
  print (some Nothing :: Maybe [Int])
  print (many Nothing :: Maybe [Int])
  print (optional (Just 3))
  print (asum [Nothing, Just 4, Just 5])
  print (liftA not (Just False))
  print (liftA3 (,,) (Just 1) (Just 2) (Just 3))
  print (Just 3 <**> Just (+ 1))
  print (2 <$ Just 9)
  print (const 1 <$> Just 0 <|> Just 9)
  print ((+) <$> Just 1 <*> Just 2 <|> Just 0)
  print (getZipList (ZipList [(+ 1), (* 2)] <*> ZipList [10, 20, 30]))
  print (ZipList [1, 2, 3])
  print (getZipList (ZipList [1, 2] <|> ZipList [7, 8, 9]))
  print (getConst (Const "k" :: Const String Int))
  print (getConst (Const "ab" <*> (Const "cd" :: Const String Int)))
  print (unwrapMonad (fmap (+ 1) (WrapMonad (Just 4))))
  print (runP (many (item 'a')) "aab")
  print (runP (some (item 'a')) "b")
  print (runP ((,) <$> some (item 'a') <*> many (item 'b')) "aabbc")
