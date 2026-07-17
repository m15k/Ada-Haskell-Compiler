package body AHC.Modules is

   use type Names.Name_Id;

   function Never_Eq (A, B : Module_Entry) return Boolean is
      pragma Unreferenced (A, B);
   begin
      return False;
   end Never_Eq;

   function Find
     (Reg : Registry; Name : Names.Name_Id) return Natural is
   begin
      for I in 1 .. Reg.Mods.Last_Index loop
         if Reg.Mods (I).Name = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find;

end AHC.Modules;
