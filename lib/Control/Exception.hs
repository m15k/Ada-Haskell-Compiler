module Control.Exception
  ( SomeException, Exception (..)
  , ErrorCall (..), ArithException (..), IOException, ExitCode (..)
  , throw, throwIO, catch, handle, try, evaluate
  , bracket, bracket_, finally, onException
  ) where

import System.Exit (ExitCode (..))

-- base's Control.Exception, closed (docs/exceptions-design-note.md):
-- SomeException is the runtime's exception value - a KIND and a
-- payload, reached through the prim* accessors - and the Exception
-- class dispatches on that kind. Four types can be thrown and
-- caught: ErrorCall (error, undefined, pattern-match failure),
-- ArithException, IOException, and ExitCode. A program cannot
-- declare its own (that needs Typeable; Haskell 2010 has no user
-- exception types), which is written into EXCLUSIONS.md.

class Show e => Exception e where
  toException :: e -> SomeException
  fromException :: SomeException -> Maybe e
  displayException :: e -> String
  displayException = show

instance Show SomeException where
  showsPrec p se = case primExcKind se of
    1 -> showsPrec p (ErrorCall (primExcMessage se))
    2 -> showsPrec p (arithFromCode (primExcCode se))
    3 -> showsPrec p (primExcIO se)
    _ -> showsPrec p (exitFromCode (primExcCode se))

instance Exception SomeException where
  toException = id
  fromException = Just

data ErrorCall = ErrorCall String deriving (Eq, Ord)

instance Show ErrorCall where
  showsPrec _ (ErrorCall m) = showString m

instance Exception ErrorCall where
  toException (ErrorCall m) = primExcErrorCall m
  fromException se
    | primExcKind se == 1 = Just (ErrorCall (primExcMessage se))
    | otherwise = Nothing

-- base's order; the index is the runtime's code.
data ArithException
  = Overflow | Underflow | LossOfPrecision | DivideByZero | Denormal
  | RatioZeroDenominator
  deriving (Eq, Ord, Enum, Bounded)

instance Show ArithException where
  showsPrec _ e = showString (case e of
    Overflow -> "arithmetic overflow"
    Underflow -> "arithmetic underflow"
    LossOfPrecision -> "loss of precision"
    DivideByZero -> "divide by zero"
    Denormal -> "denormal"
    RatioZeroDenominator -> "Ratio has zero denominator")

arithFromCode :: Int -> ArithException
arithFromCode = toEnum

instance Exception ArithException where
  toException = primExcArith . fromEnum
  fromException se
    | primExcKind se == 2 = Just (arithFromCode (primExcCode se))
    | otherwise = Nothing

instance Exception IOException where
  toException = primExcFromIO
  fromException se
    | primExcKind se == 3 = Just (primExcIO se)
    | otherwise = Nothing

exitFromCode :: Int -> ExitCode
exitFromCode 0 = ExitSuccess
exitFromCode n = ExitFailure n

exitToCode :: ExitCode -> Int
exitToCode ExitSuccess = 0
exitToCode (ExitFailure n) = n

instance Exception ExitCode where
  toException = primExcExit . exitToCode
  fromException se
    | primExcKind se == 4 = Just (exitFromCode (primExcCode se))
    | otherwise = Nothing

throw :: Exception e => e -> a
throw e = primThrow (toException e)

throwIO :: Exception e => e -> IO a
throwIO e = primThrowIO (toException e)

catch :: Exception e => IO a -> (e -> IO a) -> IO a
catch act h = primCatch act (\se -> case fromException se of
                                      Just e -> h e
                                      Nothing -> primThrowIO se)

handle :: Exception e => (e -> IO a) -> IO a -> IO a
handle h act = catch act h

try :: Exception e => IO a -> IO (Either e a)
try act = catch (act >>= \r -> return (Right r)) (\e -> return (Left e))

-- Force to WHNF inside the action, so a raise is raised here.
evaluate :: a -> IO a
evaluate = primEvaluate

onException :: IO a -> IO b -> IO a
onException act what = primCatch act (\se -> what >> primThrowIO se)

bracket :: IO a -> (a -> IO b) -> (a -> IO c) -> IO c
bracket acquire release body =
  acquire >>= \a ->
  (body a `onException` release a) >>= \r ->
  release a >>
  return r

bracket_ :: IO a -> IO b -> IO c -> IO c
bracket_ before after body = bracket before (const after) (const body)

finally :: IO a -> IO b -> IO a
finally act fin = (act `onException` fin) >>= \r -> fin >> return r
