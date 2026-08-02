--  ahc.toml: the project manifest (M129). Bare `ahc build` in a
--  directory holding one reads it instead of requiring a source
--  argument. Deliberately the smallest honest manifest: flat
--  string/boolean/integer keys, no sections, no dependencies -
--  there is no package ecosystem to manage, so a "build system"
--  reduces to naming the root module and the flags a project
--  always wants. Explicit CLI flags and environment variables
--  override manifest values (operator beats project defaults).

with Ada.Strings.Unbounded;

package AHC.Manifest is

   use Ada.Strings.Unbounded;

   type Project is record
      Main      : Unbounded_String;  --  required: the root .hs file
      Output    : Unbounded_String;  --  default: main minus .hs
      Cflags    : Unbounded_String;  --  appended after AHC_CFLAGS
      Ldflags   : Unbounded_String;  --  appended after AHC_LDFLAGS
      GC        : Unbounded_String;  --  boehm|own|none; env wins
      Unchecked : Boolean := False;
      No_Opt    : Boolean := False;
      Lib       : Boolean := False;
      Jobs      : Natural := 0;
   end record;

   function Load (Path : String; P : out Project) return Boolean;
   --  Parse Path. False (with a message on stderr naming the line)
   --  on a malformed line, an unknown key, or a missing main.

end AHC.Manifest;
