module System.IO.Error
  ( IOError, IOErrorType, ioError, userError
  , mkIOError, annotateIOError, modifyIOError
  , catchIOError, tryIOError
  , ioeGetErrorType, ioeGetLocation, ioeGetErrorString, ioeGetFileName
  , ioeSetErrorType, ioeSetErrorString, ioeSetLocation, ioeSetFileName
  , isAlreadyExistsError, isDoesNotExistError, isAlreadyInUseError
  , isFullError, isEOFError, isIllegalOperation, isPermissionError
  , isUserError
  , alreadyExistsErrorType, doesNotExistErrorType, alreadyInUseErrorType
  , fullErrorType, eofErrorType, illegalOperationErrorType
  , permissionErrorType, userErrorType
  , isAlreadyExistsErrorType, isDoesNotExistErrorType
  , isAlreadyInUseErrorType, isFullErrorType, isEOFErrorType
  , isIllegalOperationErrorType, isPermissionErrorType, isUserErrorType
  ) where

import System.IO (Handle)

-- Library Report chapter 42. An IOError is a runtime value
-- (docs/exceptions-design-note.md): four fields - type, location,
-- description, filename - reached through the prim* accessors, and
-- (the type index table: 0 AlreadyExists 1 NoSuchThing 2 ResourceBusy
-- 3 ResourceExhausted 4 EOF 5 IllegalOperation 6 PermissionDenied
-- 7 UserError 8 InappropriateType 9 OtherError 10 InvalidArgument -
-- the last two have no Report constant, only a Show text)
-- rebuilt whole by the ioeSet* functions. The handle field the
-- Report also names is not stored (GHC's own IOErrors from openFile
-- carry none either): ioeGetHandle/ioeSetHandle are absent, and the
-- Maybe Handle arguments below are accepted and ignored.

-- IOErrorType is ABSTRACT in the Report; a newtype over the
-- runtime's table index keeps the constructor namespace (which is
-- program-global in AHC) free of names like EOF and UserError.
newtype IOErrorType = MkIOErrorType Int deriving (Eq, Ord)

instance Show IOErrorType where
  showsPrec _ (MkIOErrorType t) = showString (case t of
    0 -> "already exists"
    1 -> "does not exist"
    2 -> "resource busy"
    3 -> "resource exhausted"
    4 -> "end of file"
    5 -> "illegal operation"
    6 -> "permission denied"
    7 -> "user error"
    8 -> "inappropriate type"
    10 -> "invalid argument"
    _ -> "failed")

alreadyExistsErrorType, doesNotExistErrorType, alreadyInUseErrorType,
  fullErrorType, eofErrorType, illegalOperationErrorType,
  permissionErrorType, userErrorType :: IOErrorType
alreadyExistsErrorType    = MkIOErrorType 0
doesNotExistErrorType     = MkIOErrorType 1
alreadyInUseErrorType     = MkIOErrorType 2
fullErrorType             = MkIOErrorType 3
eofErrorType              = MkIOErrorType 4
illegalOperationErrorType = MkIOErrorType 5
permissionErrorType       = MkIOErrorType 6
userErrorType             = MkIOErrorType 7

isAlreadyExistsErrorType, isDoesNotExistErrorType, isAlreadyInUseErrorType,
  isFullErrorType, isEOFErrorType, isIllegalOperationErrorType,
  isPermissionErrorType, isUserErrorType :: IOErrorType -> Bool
isAlreadyExistsErrorType    = (== alreadyExistsErrorType)
isDoesNotExistErrorType     = (== doesNotExistErrorType)
isAlreadyInUseErrorType     = (== alreadyInUseErrorType)
isFullErrorType             = (== fullErrorType)
isEOFErrorType              = (== eofErrorType)
isIllegalOperationErrorType = (== illegalOperationErrorType)
isPermissionErrorType       = (== permissionErrorType)
isUserErrorType             = (== userErrorType)

ioeGetErrorType :: IOError -> IOErrorType
ioeGetErrorType e = MkIOErrorType (primIoeType e)

ioeGetLocation :: IOError -> String
ioeGetLocation = primIoeLocation

-- The description for a user error, the type's text otherwise.
ioeGetErrorString :: IOError -> String
ioeGetErrorString e
  | isUserError e = primIoeDescription e
  | otherwise     = show (ioeGetErrorType e)

ioeGetFileName :: IOError -> Maybe FilePath
ioeGetFileName = primIoeFilename

-- GHC's ioeSet*/annotateIOError are record updates, so they force the
-- IOError: `ioeSetLocation undefined "l"` is undefined, not "l".
rebuild :: Int -> String -> String -> Maybe FilePath -> IOError
rebuild = primMkIOError

forcing :: IOError -> IOError -> IOError
forcing e r = e `seq` r

ioeSetErrorType :: IOError -> IOErrorType -> IOError
ioeSetErrorType e (MkIOErrorType t) = forcing e
  (rebuild t (primIoeLocation e) (primIoeDescription e) (primIoeFilename e))

ioeSetErrorString :: IOError -> String -> IOError
ioeSetErrorString e s = forcing e
  (rebuild (primIoeType e) (primIoeLocation e) s (primIoeFilename e))

ioeSetLocation :: IOError -> String -> IOError
ioeSetLocation e l = forcing e
  (rebuild (primIoeType e) l (primIoeDescription e) (primIoeFilename e))

ioeSetFileName :: IOError -> FilePath -> IOError
ioeSetFileName e f = forcing e
  (rebuild (primIoeType e) (primIoeLocation e) (primIoeDescription e) (Just f))

isAlreadyExistsError, isDoesNotExistError, isAlreadyInUseError,
  isFullError, isEOFError, isIllegalOperation, isPermissionError,
  isUserError :: IOError -> Bool
isAlreadyExistsError = isAlreadyExistsErrorType . ioeGetErrorType
isDoesNotExistError  = isDoesNotExistErrorType . ioeGetErrorType
isAlreadyInUseError  = isAlreadyInUseErrorType . ioeGetErrorType
isFullError          = isFullErrorType . ioeGetErrorType
isEOFError           = isEOFErrorType . ioeGetErrorType
isIllegalOperation   = isIllegalOperationErrorType . ioeGetErrorType
isPermissionError    = isPermissionErrorType . ioeGetErrorType
isUserError          = isUserErrorType . ioeGetErrorType

mkIOError :: IOErrorType -> String -> Maybe Handle -> Maybe FilePath -> IOError
mkIOError (MkIOErrorType t) loc _ path = rebuild t loc "" path

-- GHC's: the location is replaced; a filename given here wins over
-- the one already set (`path `mplus` ioe_filename`).
annotateIOError :: IOError -> String -> Maybe Handle -> Maybe FilePath -> IOError
annotateIOError e loc _ path = forcing e
  (rebuild (primIoeType e) loc (primIoeDescription e)
           (case path of
              Just f -> Just f
              Nothing -> primIoeFilename e))

catchIOError :: IO a -> (IOError -> IO a) -> IO a
catchIOError act h =
  primCatch act (\se -> if primExcKind se == 3 then h (primExcIO se)
                        else primThrowIO se)

tryIOError :: IO a -> IO (Either IOError a)
tryIOError act = catchIOError (act >>= \r -> return (Right r))
                              (\e -> return (Left e))

modifyIOError :: (IOError -> IOError) -> IO a -> IO a
modifyIOError f act = catchIOError act (\e -> ioError (f e))
