--  Process and file plumbing shared by the build (clang, ar,
--  pkg-config) and the fetcher (git): spawn with inherited stdio,
--  spawn with captured output, slurp a file, and the small string
--  conveniences the shell scripts used to provide for free.
--  Factored out of AHC.Build verbatim - behavior is part of the
--  build's contract (run_build.sh), so nothing here may drift.

with Ada.Containers.Indefinite_Vectors;

with GNAT.OS_Lib;

package AHC.Shell is

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Positive, String);

   function Slurp (Path : String) return String;
   --  Whole file as a string. Propagates on a missing file.

   --  $(cat file): command substitution strips trailing newlines.
   function Trim_Trailing (S : String) return String;

   --  A flags string becomes argv words the way the shell's
   --  unquoted expansion did: split on whitespace, empties dropped.
   procedure Append_Words
     (Args : in out String_Vectors.Vector; Flags : String);

   function To_Arg_List
     (Args : String_Vectors.Vector)
      return GNAT.OS_Lib.Argument_List_Access;

   procedure Free_Args (A : in out GNAT.OS_Lib.Argument_List_Access);

   procedure Put_Command
     (Prog : String; Args : String_Vectors.Vector);

   --  Spawn Prog with Args, stdio inherited (a failing clang or
   --  git prints its own message). True when the exit code is zero;
   --  False with a message when Prog is not on PATH.
   function Run
     (Prog : String; Args : String_Vectors.Vector; Verbose : Boolean)
      return Boolean;

   --  Spawn Prog with Args, stdout+stderr captured (the script's
   --  `2>/dev/null` probes). Returns the trimmed output; Ok is the
   --  zero-exit test (False too when Prog is not on PATH).
   function Capture
     (Prog : String; Args : String_Vectors.Vector;
      Ok : out Boolean) return String;

   --  The one- and two-argument shape the build's probes use.
   function Capture
     (Prog : String; Arg_1 : String; Arg_2 : String := "";
      Ok : out Boolean) return String;

end AHC.Shell;
