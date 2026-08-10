with AHC.Semver; use AHC.Semver;

with Test_Harness; use Test_Harness;

package body Test_Semver is

   procedure Run is
      V, W : Version;
   begin
      Start_Suite ("Semver");

      Check (Parse ("1.2.3", V), "plain triple parses");
      Check (V.Major = 1 and V.Minor = 2 and V.Patch = 3,
             "components land");
      Check_Equal (Image (V), "1.2.3", "image round-trips");
      Check (Parse ("0.0.0", V), "all zeros parse");
      Check (Parse ("10.20.30", V), "multi-digit components parse");

      Check (not Parse ("1.2", V), "two components rejected");
      Check (not Parse ("1.2.3.4", V), "four components rejected");
      Check (not Parse ("v1.2.3", V), "v prefix rejected here");
      Check (not Parse ("1.2.x", V), "non-digit component rejected");
      Check (not Parse ("1..3", V), "empty component rejected");
      Check (not Parse ("", V), "empty string rejected");
      Check (not Parse ("1.2.3-rc1", V), "prerelease rejected");

      Check (Parse ("1.2.3", V) and Parse ("1.2.4", W),
             "comparison fixtures parse");
      Check (V < W, "patch orders");
      Check (not (W < V), "patch orders strictly");
      Check (Parse ("1.9.9", V) and then Parse ("2.0.0", W)
             and then V < W,
             "major dominates");
      Check (Parse ("1.2.9", V) and then Parse ("1.10.0", W)
             and then V < W,
             "minor compares numerically, not lexically");
      Check (Parse ("3.1.4", V) and then Parse ("3.1.4", W)
             and then not (V < W) and then not (W < V),
             "equal versions are unordered");
   end Run;

end Test_Semver;
