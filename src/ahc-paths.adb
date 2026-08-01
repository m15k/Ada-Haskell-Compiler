with Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;

with GNAT.OS_Lib;

package body AHC.Paths is

   --  Root of the installation the running binary belongs to (the
   --  parent of the executable's own directory: bin/ahc lives under
   --  a checkout or an installed tree). "" when the executable
   --  cannot be located - then only the historical arms apply.

   function Compute_Install_Root return String is
      use GNAT.OS_Lib;
      Cmd : constant String := Ada.Command_Line.Command_Name;
      Exe : String_Access :=
        (if Ada.Strings.Fixed.Index (Cmd, "/") > 0
         then new String'(Normalize_Pathname (Cmd))
         else Locate_Exec_On_Path (Cmd));
   begin
      if Exe = null then
         return "";
      end if;
      declare
         R : constant String := Normalize_Pathname
           (Ada.Directories.Containing_Directory (Exe.all) & "/..");
      begin
         Free (Exe);
         return R;
      end;
   end Compute_Install_Root;

   Install_Root : constant String := Compute_Install_Root;

   --  The shared cascade: env override wins outright (even if the
   --  target is missing, so the eventual error names the place the
   --  user asked for); otherwise first existing of CWD-relative,
   --  install-relative; otherwise the CWD-relative default.

   function Resolve (Env_Var, Rel : String) return String is
   begin
      if Ada.Environment_Variables.Exists (Env_Var) then
         return Ada.Environment_Variables.Value (Env_Var);
      end if;
      if Ada.Directories.Exists (Rel) then
         return Rel;
      end if;
      if Install_Root /= ""
        and then Ada.Directories.Exists (Install_Root & "/" & Rel)
      then
         return Install_Root & "/" & Rel;
      end if;
      return Rel;
   end Resolve;

   function Prelude_File return String is
     (Resolve ("AHC_PRELUDE", "prelude/Prelude.hs"));

   function Runtime_Dir return String is
     (Resolve ("AHC_RUNTIME", "runtime"));

   function Stdlib_File (Rel : String) return String is
   begin
      if Ada.Environment_Variables.Exists ("AHC_LIB") then
         declare
            P : constant String :=
              Ada.Environment_Variables.Value ("AHC_LIB") & "/" & Rel;
         begin
            if Ada.Directories.Exists (P) then
               return P;
            end if;
         end;
      end if;
      if Ada.Directories.Exists ("lib/" & Rel) then
         return "lib/" & Rel;
      end if;
      if Install_Root /= ""
        and then Ada.Directories.Exists (Install_Root & "/lib/" & Rel)
      then
         return Install_Root & "/lib/" & Rel;
      end if;
      return "";
   end Stdlib_File;

end AHC.Paths;
