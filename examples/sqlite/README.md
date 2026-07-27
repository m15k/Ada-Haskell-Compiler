# ahcsql — binding a real C library

`ahcsql.hs` binds sqlite3 (the copy that ships with the OS — no
install, one pragma: `{-# OPTIONS_AHC_LINK -lsqlite3 #-}`) and runs
a complete session against an in-memory database: create, insert,
query, error, close.

Every part of the FFI crosses the boundary in ~80 lines:

- **out-parameters** — `sqlite3_open` writes the handle through a
  `sqlite3**`: `mallocBytes 8`, pass the pointer, `peekPtr` it back;
- **strings both directions** — SQL text in, column values out;
- **fixed-width types** — every sqlite result code is a real C
  `int`, so the imports say `CInt` and mean it;
- **a Haskell closure as a C function pointer** — the row callback
  handed to `sqlite3_exec` is a lambda; sqlite calls it once per
  row with `char **argv`, and the Haskell side walks the array with
  `peekPtr`/`peekCString`, NULL-safe via `nullPtr`;
- **the C library's own errors** — a bad query's message comes back
  through `sqlite3_errmsg` and `peekCString`.

Build and run:

    scripts/ahc-build.sh examples/sqlite/ahcsql.hs ahcsql
    ./ahcsql

`scripts/run_sqlite.sh` keeps it green against `expected.out`.
