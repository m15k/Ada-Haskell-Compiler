-- base's Control.Exception, the portable subset: catch/handle/try
-- dispatch by handler type, throw/throwIO, evaluate, bracket and
-- finally ordering, nested rethrow, ExitCode as an exception, and
-- the lazy-result gotcha.
import Control.Exception
import System.Exit
import System.IO

main :: IO ()
main = do
  -- ErrorCall, by pattern (its show carries a call stack in GHC)
  catch (evaluate (error "boom" :: Int) >> return ())
        (\(ErrorCall m) -> putStrLn ("ErrorCall: " ++ m))
  r1 <- try (evaluate (head ([] :: [Int])))
  putStrLn (either (\(ErrorCall m) -> m) show r1)
  -- ArithException
  r2 <- try (evaluate (1 `div` (0 :: Int))) :: IO (Either ArithException Int)
  print r2
  r3 <- try (evaluate (10 `mod` (0 :: Integer))) :: IO (Either ArithException Integer)
  print r3
  catch (evaluate (1 `quot` (0 :: Int)) >> return ())
        (\e -> putStrLn ("some: " ++ show (e :: SomeException)))
  r4 <- try (throwIO Overflow) :: IO (Either ArithException ())
  print r4
  print [Overflow, Underflow, LossOfPrecision, DivideByZero, Denormal,
         RatioZeroDenominator]
  -- IOException
  r5 <- try (readFile "/nonexistent/ahc/zz.txt") :: IO (Either IOException String)
  either print putStr r5
  handle (\e -> putStrLn ("handle: " ++ show (e :: IOException)))
         (ioError (userError "h"))
  -- a handler for the WRONG type lets it pass to the next one
  catch (catch (throwIO (userError "typed"))
               (\e -> putStrLn ("arith? " ++ show (e :: ArithException))))
        (\e -> putStrLn ("io: " ++ show (e :: IOException)))
  -- nested + rethrow of the same value
  catch (catch (throwIO (userError "inner"))
               (\e -> do putStrLn ("inner handler: " ++ show (e :: IOException))
                         throwIO e))
        (\e -> putStrLn ("outer handler: " ++ show (e :: IOException)))
  -- throw in pure code
  r6 <- try (evaluate (throw (ErrorCall "thrown") :: Int)) :: IO (Either ErrorCall Int)
  print r6
  print (ErrorCall "a" == ErrorCall "a", ErrorCall "a" < ErrorCall "b")
  -- bracket / finally ordering
  r7 <- try (bracket (putStrLn "acquire" >> return 7)
                     (\_ -> putStrLn "release")
                     (\n -> do putStrLn ("use " ++ show n)
                               _ <- throwIO (userError "in use")
                               return n)) :: IO (Either IOException Int)
  print r7
  r8 <- bracket (return 'x') (\_ -> putStrLn "released") (\c -> return [c, c])
  putStrLn r8
  (putStrLn "body" >> throwIO (userError "fin"))
    `catch` (\e -> putStrLn ("caught " ++ show (e :: IOException)))
    `finally` putStrLn "finally ran"
  bracket_ (putStrLn "before") (putStrLn "after") (putStrLn "between")
  -- withFile closes on the way out
  writeFile "/tmp/ahc_conf_exception.txt" "line\n"
  r9 <- try (withFile "/tmp/ahc_conf_exception.txt" ReadMode
               (\h -> hGetLine h >>= putStrLn >> hGetLine h >>= putStrLn))
          :: IO (Either IOException ())
  either print return r9
  -- ExitCode is an exception
  r10 <- try (exitWith (ExitFailure 3)) :: IO (Either ExitCode ())
  print r10
  catch (exitWith (ExitFailure 4))
        (\e -> putStrLn ("some exit: " ++ show (e :: SomeException)))
  r11 <- try exitSuccess :: IO (Either ExitCode ())
  print r11
  -- laziness: not caught, because nothing forced it
  x <- catch (return (error "lazy")) (\e -> const (return 0) (e :: SomeException)) :: IO Int
  r12 <- try (evaluate x) :: IO (Either ErrorCall Int)
  putStrLn (either (const "escaped catch, caught later") show r12)
  -- displayException and SomeException's show for the plain types
  putStrLn (displayException (userError "shown"))
  putStrLn (displayException DivideByZero)
  print (toException DivideByZero)
  print (fromException (toException (userError "back")) :: Maybe IOException)
  print (fromException (toException (userError "back")) :: Maybe ArithException)
  -- a real exit, uncaught: the program ends here with code 2
  hFlush stdout
  exitWith (ExitFailure 2)
  putStrLn "unreached"
