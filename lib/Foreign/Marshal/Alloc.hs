module Foreign.Marshal.Alloc (mallocBytes, free) where

-- malloc, alloca, allocaBytes, calloc, realloc need Storable's sizeOf
-- or a bracket over it and are absent; mallocBytes/free are the wired
-- primitives. Raw peeks and pokes are in AHC.FFI.
