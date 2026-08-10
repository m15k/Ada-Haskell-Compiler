--  Versions for git dependencies (M135): a numeric triple and
--  nothing else. No prereleases, no build metadata, no ranges -
--  minimal version selection only ever needs "parse" and "<",
--  and refusing the rest keeps version comparison total and
--  obvious. Manifests write "1.2.0"; git tags are probed as
--  "v1.2.0" then "1.2.0".

package AHC.Semver is

   type Version is record
      Major, Minor, Patch : Natural := 0;
   end record;

   function Parse (S : String; V : out Version) return Boolean;
   --  "X.Y.Z", each a bare natural. False on anything else -
   --  including "v" prefixes (strip before calling), empty
   --  components, and a fourth component.

   function "<" (L, R : Version) return Boolean;
   --  Lexicographic on (Major, Minor, Patch).

   function Image (V : Version) return String;
   --  "X.Y.Z", no leading v.

end AHC.Semver;
