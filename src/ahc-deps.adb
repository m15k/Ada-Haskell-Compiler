with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Containers.Indefinite_Vectors;
with Ada.Directories;
with Ada.Strings.Hash;
with Ada.Text_IO;

with GNAT.OS_Lib;

with AHC.Fetch;
with AHC.Semver;

package body AHC.Deps is

   use type AHC.Manifest.Dep_Kind;

   package String_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type        => String,
      Hash                => Ada.Strings.Hash,
      Equivalent_Elements => "=");

   package String_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => String,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package Version_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => AHC.Semver.Version,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=",
      "="             => AHC.Semver."=");

   package String_Queues is new Ada.Containers.Indefinite_Vectors
     (Positive, String);

   procedure Err (Msg : String) is
   begin
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "ahc: " & Msg);
   end Err;

   --  The path walk's accumulated state, shared between the local
   --  closure and the later walks of fetched trees so dedup and
   --  name identity span both.
   type Walk_State is record
      Seen     : String_Sets.Set;   --  every directory ever taken
      On_Stack : String_Sets.Set;   --  the walk's current spine
      By_Name  : String_Maps.Map;   --  name -> directory it means
      Ok       : Boolean := True;
   end record;

   --  Walk Dir's manifest: path dependencies recurse (depth-first,
   --  manifest order), git dependencies are appended to Git_Out -
   --  except the start manifest's own when Collect_Git_Here is
   --  False (the caller holds the root manifest verbatim).
   procedure Walk
     (St               : in out Walk_State;
      Roots            : in out Root_Vectors.Vector;
      Git_Out          : in out
        AHC.Manifest.Dependency_Vectors.Vector;
      Collect_Git_Here : Boolean;
      Dir              : String)
   is
      Manifest_Path : constant String := Dir & "/ahc.toml";
      P             : AHC.Manifest.Project;
   begin
      if not Ada.Directories.Exists (Manifest_Path) then
         return;   --  a bare module tree: nothing more to walk
      end if;
      if not AHC.Manifest.Load
        (Manifest_Path, P, Require_Main => False)
      then
         St.Ok := False;
         return;
      end if;
      St.On_Stack.Include (Dir);
      for D of P.Deps loop
         exit when not St.Ok;
         if D.Kind = AHC.Manifest.Git_Dep then
            if Collect_Git_Here then
               Git_Out.Append (D);
            end if;
         else
            declare
               Name : constant String := To_String (D.Name);
               Full : constant String :=
                 GNAT.OS_Lib.Normalize_Pathname
                   (Dir & "/" & To_String (D.Path));
            begin
               if not Ada.Directories.Exists (Full) then
                  Err ("dependency '" & Name
                       & "': no such directory " & Full
                       & " (from " & Manifest_Path & ")");
                  St.Ok := False;
               elsif St.On_Stack.Contains (Full) then
                  Err ("dependency cycle through '" & Full & "'");
                  St.Ok := False;
               elsif St.By_Name.Contains (Name)
                 and then St.By_Name (Name) /= Full
               then
                  Err ("dependency '" & Name & "' means both "
                       & St.By_Name (Name) & " and " & Full);
                  St.Ok := False;
               elsif not St.Seen.Contains (Full) then
                  St.Seen.Include (Full);
                  St.By_Name.Include (Name, Full);
                  Roots.Append
                    (Dep_Root'(Name => To_Unbounded_String (Name),
                               Dir  => To_Unbounded_String (Full)));
                  Walk (St, Roots, Git_Out, True, Full);
               end if;
            end;
         end if;
      end loop;
      St.On_Stack.Exclude (Dir);
   end Walk;

   function Collect_Roots
     (Manifest_Dir : String;
      Roots        : out Root_Vectors.Vector) return Boolean
   is
      St      : Walk_State;
      Ignored : AHC.Manifest.Dependency_Vectors.Vector;
   begin
      Roots.Clear;
      Walk (St, Roots, Ignored, False,
            GNAT.OS_Lib.Normalize_Pathname (Manifest_Dir));
      return St.Ok;
   end Collect_Roots;

   ----------------------------------------------------------------
   --  Minimal version selection with root pins.

   function Resolve
     (Root_Deps  : AHC.Manifest.Dependency_Vectors.Vector;
      Local_Deps : AHC.Manifest.Dependency_Vectors.Vector;
      Deps_Of    : access function
        (Clone_URL, Ref : String;
         Is_Version     : Boolean;
         Deps           : out AHC.Manifest.Dependency_Vectors.Vector)
        return Boolean;
      Selected   : out Selection_Vectors.Vector) return Boolean
   is
      Overrides   : String_Sets.Set;   --  root path dep names
      Min         : Version_Maps.Map;  --  url -> min version
      Pin         : String_Maps.Map;   --  url -> root pin, verbatim
      Clone_Of    : String_Maps.Map;   --  url -> first clone URL
      Nick_Of     : String_Maps.Map;   --  url -> first nickname
      URL_Of_Name : String_Maps.Map;   --  name -> url
      Done_Ref    : String_Maps.Map;   --  url -> ref last expanded
      Queue       : String_Queues.Vector;
      Ok          : Boolean := True;

      procedure Raise_Min (Ident : String; V : AHC.Semver.Version) is
         use AHC.Semver;
      begin
         if not Min.Contains (Ident) or else Min (Ident) < V then
            Min.Include (Ident, V);
            Queue.Append (Ident);
         end if;
      end Raise_Min;

      --  One git dependency declaration, from the root manifest
      --  (pins select) or anywhere else (pins demote).
      procedure Note
        (D : AHC.Manifest.Dependency; From_Root : Boolean)
      is
         Name : constant String := To_String (D.Name);
      begin
         if not Ok or else D.Kind /= AHC.Manifest.Git_Dep
           or else Overrides.Contains (Name)
         then
            return;
         end if;
         declare
            Ident : constant String :=
              AHC.Fetch.Normalize_URL (To_String (D.URL));
            V     : AHC.Semver.Version;
         begin
            if URL_Of_Name.Contains (Name)
              and then URL_Of_Name (Name) /= Ident
            then
               Err ("dependency '" & Name & "' means both "
                    & URL_Of_Name (Name) & " and " & Ident);
               Ok := False;
               return;
            end if;
            URL_Of_Name.Include (Name, Ident);
            if not Clone_Of.Contains (Ident) then
               Clone_Of.Include (Ident, To_String (D.URL));
               Nick_Of.Include (Ident, Name);
               Queue.Append (Ident);
            end if;
            if D.Pin /= "" then
               declare
                  P : constant String := To_String (D.Pin);
                  T : constant String :=
                    (if P'Length > 1 and then P (P'First) = 'v'
                     then P (P'First + 1 .. P'Last) else P);
               begin
                  if From_Root then
                     if Pin.Contains (Ident)
                       and then Pin (Ident) /= P
                     then
                        Err ("conflicting root pins '"
                             & Pin (Ident) & "' and '" & P
                             & "' for " & Ident);
                        Ok := False;
                     else
                        Pin.Include (Ident, P);
                        Queue.Append (Ident);
                     end if;
                  elsif AHC.Semver.Parse (T, V) then
                     Raise_Min (Ident, V);   --  tag pin demotes
                  elsif not Pin.Contains (Ident) then
                     Err ("dependency '" & Name
                          & "' is pinned to commit '" & P
                          & "' in a transitive manifest; pin it in"
                          & " the root ahc.toml to select it");
                     Ok := False;
                  end if;
               end;
            else
               if AHC.Semver.Parse (To_String (D.Version), V) then
                  Raise_Min (Ident, V);
               end if;   --  unparseable was refused at Load
            end if;
         end;
      end Note;

      function Ref_For (Ident : String) return String is
        (if Pin.Contains (Ident) then Pin (Ident)
         else AHC.Semver.Image (Min (Ident)));

   begin
      Selected.Clear;

      for D of Root_Deps loop
         if D.Kind = AHC.Manifest.Path_Dep then
            Overrides.Include (To_String (D.Name));
         end if;
      end loop;
      for D of Root_Deps loop
         Note (D, From_Root => True);
      end loop;
      for D of Local_Deps loop
         Note (D, From_Root => False);
      end loop;

      --  The worklist: expand each URL at its currently selected
      --  ref; a raised minimum re-enqueues, so every URL is
      --  expanded at its final ref before the queue drains.
      while Ok and then not Queue.Is_Empty loop
         declare
            Ident : constant String := Queue.First_Element;
            Ref   : constant String := Ref_For (Ident);
            Deps  : AHC.Manifest.Dependency_Vectors.Vector;
         begin
            Queue.Delete_First;
            if not Done_Ref.Contains (Ident)
              or else Done_Ref (Ident) /= Ref
            then
               Done_Ref.Include (Ident, Ref);
               if Deps_Of (Clone_Of (Ident), Ref,
                           not Pin.Contains (Ident), Deps)
               then
                  for D of Deps loop
                     Note (D, From_Root => False);
                  end loop;
               else
                  Ok := False;
               end if;
            end if;
         end;
      end loop;

      if not Ok then
         return False;
      end if;

      --  Deterministic output: sorted by URL.
      declare
         Idents : String_Queues.Vector;
         package Sorting is new String_Queues.Generic_Sorting;
         C : String_Maps.Cursor := Clone_Of.First;
      begin
         while String_Maps.Has_Element (C) loop
            Idents.Append (String_Maps.Key (C));
            String_Maps.Next (C);
         end loop;
         Sorting.Sort (Idents);
         for Ident of Idents loop
            Selected.Append
              (Selection'
                 (Name       => To_Unbounded_String
                                  (Nick_Of (Ident)),
                  URL        => To_Unbounded_String (Ident),
                  Clone_URL  => To_Unbounded_String
                                  (Clone_Of (Ident)),
                  Ref        => To_Unbounded_String
                                  (Ref_For (Ident)),
                  Is_Version => not Pin.Contains (Ident)));
         end loop;
      end;
      return True;
   end Resolve;

   ----------------------------------------------------------------

   function Collect_All
     (Manifest_Dir : String;
      Roots        : out Root_Vectors.Vector;
      Fetch_Only   : Boolean := False;
      Quiet        : Boolean := False) return Boolean
   is
      Start : constant String :=
        GNAT.OS_Lib.Normalize_Pathname (Manifest_Dir);
      Manifest_Path : constant String := Start & "/ahc.toml";
      Sum_Path      : constant String := Start & "/ahc.sum";

      St        : Walk_State;
      Root_P    : AHC.Manifest.Project;
      Local_Git : AHC.Manifest.Dependency_Vectors.Vector;
      Sel       : Selection_Vectors.Vector;

      function Deps_Of
        (Clone_URL, Ref : String;
         Is_Version     : Boolean;
         Deps           : out AHC.Manifest.Dependency_Vectors.Vector)
        return Boolean
      is
         Dir : Unbounded_String;
         P   : AHC.Manifest.Project;
      begin
         Deps.Clear;
         if not AHC.Fetch.Ensure
           (Clone_URL, Ref, Is_Version, Sum_Path, Dir, Quiet)
         then
            return False;
         end if;
         if Ada.Directories.Exists (To_String (Dir) & "/ahc.toml")
         then
            if not AHC.Manifest.Load
              (To_String (Dir) & "/ahc.toml", P,
               Require_Main => False)
            then
               return False;
            end if;
            Deps := P.Deps;
         end if;
         return True;
      end Deps_Of;

   begin
      Roots.Clear;
      if not Ada.Directories.Exists (Manifest_Path) then
         return True;
      end if;
      if not AHC.Manifest.Load
        (Manifest_Path, Root_P, Require_Main => False)
      then
         return False;
      end if;

      Walk (St, Roots, Local_Git, False, Start);
      if not St.Ok then
         return False;
      end if;

      if Local_Git.Is_Empty
        and then (for all D of Root_P.Deps =>
                    D.Kind = AHC.Manifest.Path_Dep)
      then
         return True;   --  path-only project: nothing to fetch
      end if;

      if not Resolve (Root_P.Deps, Local_Git, Deps_Of'Access, Sel)
      then
         return False;
      end if;
      if Fetch_Only then
         Roots.Clear;
         return True;
      end if;

      --  Selected trees join the search path after all path roots,
      --  sorted by URL (Resolve's order), each walked for its own
      --  vendored path dependencies.
      for S of Sel loop
         declare
            Dir : Unbounded_String;
            New_Git : AHC.Manifest.Dependency_Vectors.Vector;
            Name : constant String := To_String (S.Name);
         begin
            if not AHC.Fetch.Ensure
              (To_String (S.Clone_URL), To_String (S.Ref),
               S.Is_Version, Sum_Path, Dir, Quiet => True)
            then
               return False;   --  warm from Resolve; cannot fail twice
            end if;
            declare
               D : constant String := To_String (Dir);
            begin
               if St.By_Name.Contains (Name)
                 and then St.By_Name (Name) /= D
               then
                  Err ("dependency '" & Name & "' means both "
                       & St.By_Name (Name) & " and " & D);
                  return False;
               end if;
               if not St.Seen.Contains (D) then
                  St.Seen.Include (D);
                  St.By_Name.Include (Name, D);
                  Roots.Append
                    (Dep_Root'
                       (Name => S.Name,
                        Dir  => To_Unbounded_String (D)));
                  Walk (St, Roots, New_Git, False, D);
                  if not St.Ok then
                     return False;
                  end if;
                  --  Git requirements surfacing only inside a
                  --  fetched tree's vendored subtrees never met
                  --  the resolver - refuse rather than under-link.
                  for G of New_Git loop
                     if not (for some T of Sel =>
                               To_String (T.URL) =
                               AHC.Fetch.Normalize_URL
                                 (To_String (G.URL)))
                     then
                        Err ("dependency '" & To_String (G.Name)
                             & "' (git) is declared inside fetched"
                             & " dependency '" & Name
                             & "'s vendored tree; git dependencies"
                             & " must be reachable from the root"
                             & " manifest");
                        return False;
                     end if;
                  end loop;
               end if;
            end;
         end;
      end loop;
      return St.Ok;
   end Collect_All;

end AHC.Deps;
