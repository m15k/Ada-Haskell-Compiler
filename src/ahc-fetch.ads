--  Fetching git dependencies into the shared module cache (M135).
--  Layout: <cache>/<identity>@<ref>/ where <cache> is $AHC_MOD or
--  ~/.ahc/mod, <identity> is the URL without its scheme, and <ref>
--  is a version image ("1.2.0") or a pin as written. A fetched
--  tree has its .git stripped and is verified against the
--  project's ahc.sum - a Go-style directory hash, recorded on
--  first fetch, hard-failed on mismatch ever after. The cache is
--  content, not state: deleting any entry only means refetching.

with Ada.Strings.Unbounded;

package AHC.Fetch is

   use Ada.Strings.Unbounded;

   function Cache_Root return String;
   --  $AHC_MOD if set, else $HOME/.ahc/mod.

   function Normalize_URL (URL : String) return String;
   --  The package identity: scheme kept, one trailing '/' and a
   --  trailing '.git' stripped.

   function Identity_Path (URL : String) return String;
   --  The identity without its scheme, for cache paths and
   --  ahc.sum lines: "https://github.com/u/foo/" -> "github.com/u/foo".

   function Dirhash (Dir : String) return String;
   --  sha256 over one line per regular file under Dir,
   --  "hex(sha256(file))  relpath" + LF, relpaths sorted. The
   --  Go dirhash idea with hex spelling throughout.

   function Ensure
     (Clone_URL  : String;    --  as written in the manifest
      Ref        : String;    --  version image or pin, as recorded
      Is_Version : Boolean;   --  probe tags "v<Ref>" then "<Ref>"
      Sum_Path   : String;    --  the project's ahc.sum
      Dir        : out Unbounded_String;
      Quiet      : Boolean := False) return Boolean;
   --  Make the cache entry for (Clone_URL, Ref) present and
   --  verified; Dir is its directory. A cached tree is re-hashed
   --  and checked against ahc.sum every time (small trees, cheap
   --  honesty). A fresh fetch clones quietly, strips .git, hashes,
   --  then either matches the existing ahc.sum line or appends a
   --  new one; only then is the tree moved into place. False with
   --  a message on stderr on clone failure, hash mismatch, or an
   --  unwritable cache.

end AHC.Fetch;
