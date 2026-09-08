-- An exception crossing a task boundary travels as a VALUE and is
-- never rendered there: rendering forces the message, and forcing at
-- the boundary (every catch frame already out of reach) turned a
-- catchable IOError into whatever its lazy description raised, or
-- into a fatal <<loop>> when the message mentioned the thunk being
-- evaluated. Found by the M137 adversarial review.
import Control.Concurrent.Scoped
import Control.Exception
import System.IO.Error

main :: IO ()
main = do
  r <- tryIOError (scope (\s -> do
          t <- spawn s (ioError (userError (error "inner")) :: IO ())
          await t))
  putStrLn (either (\e -> "parent caught an IOError; user error? "
                          ++ show (isUserError e))
                   (const "no exception") r)
  let xs = error ("xs has " ++ show (length (xs :: [Int])) ++ " elements") :: [Int]
  r2 <- try (scope (\s -> spawn s (evaluate (length xs)) >>= await))
  putStrLn (either (\e -> "parent caught something: kind "
                          ++ show (primExcKind (e :: SomeException)))
                   show r2)
  -- and the message is still there when someone does look
  r3 <- try (scope (\s -> spawn s (ioError (userError "plain")) >>= await))
  putStrLn (either (\e -> "shown: " ++ show (e :: IOException)) (const "no") r3)
