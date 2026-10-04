#!/usr/bin/env bash
# The Prelude's export list must be exactly what GHC's Prelude exports
# (`ghc -e ':browse Prelude'`), except for the names documented as
# absent on the "ABSENT-NAMES:" line at the top of prelude/Prelude.hs.
# Any other difference, in either direction, fails. Needs ghc and
# python3; takes about a second.
set -u
cd "$(dirname "$0")/.."
GHC="${GHC:-$HOME/.ghcup/bin/ghc}"
[ -x "$GHC" ] || GHC=$(command -v ghc) || { echo "check_prelude_exports: no ghc" >&2; exit 2; }
out="${TMPDIR:-/tmp}/ahc_browse_prelude.$$"
"$GHC" -e ':browse Prelude' > "$out" 2>/dev/null || { echo "check_prelude_exports: ghc failed" >&2; rm -f "$out"; exit 2; }
python3 - "$out" <<'PY'
import re, sys
browse = open(sys.argv[1]).read().split("\n")
src = open("prelude/Prelude.hs").read()

# --- GHC's side
vals, types, cons_of = set(), set(), {}
for l in browse:
    if l.startswith("type ") and "::" in l:
        continue
    m = re.match(r"^(class|data|newtype|type)\s+(.*)$", l)
    if m:
        kind, rest = m.groups()
        if kind == "class":
            rest = rest.split(" where")[0]
            if "=>" in rest:
                rest = rest.split("=>")[-1]
            types.add(rest.split()[0])
        else:
            name = rest.split("=")[0].split()[0]
            types.add(name)
            if "=" in rest and kind in ("data", "newtype"):
                cs = [a.strip().split()[0] for a in rest.split("=", 1)[1].split("|")]
                cs = [c for c in cs if "." not in c and "#" not in c]
                if cs:
                    cons_of[name] = cs
        continue
    m = re.match(r"^\s*(\(?[^\s]+?\)?) ::", l)
    if m:
        n = m.group(1)
        if re.match(r"^(\w+\.)+\w", n.strip("()")) and not n.startswith("("):
            continue                    # a qualified, unexported method
        vals.add(n.strip("()"))
types.discard("(~)")
ghc = set(vals) | set(types) | {c for cs in cons_of.values() for c in cs}

# --- AHC's side: the export list
m = re.search(r"^module Prelude\s*\((.*?)^\s*\) where", src, re.S | re.M)
if not m:
    sys.exit("check_prelude_exports: no `module Prelude (...) where` header")
body = re.sub(r"--[^\n]*", "", m.group(1))
ahc = set()
for item in re.findall(r"\(\s*[^\s()]+\s*\)|[A-Za-z_][\w']*(?:\s*\(\.\.\))?", body):
    item = item.strip()
    if item.endswith("(..)"):
        t = item[:-4].strip()
        ahc.add(t)
        ahc.update(cons_of.get(t, []))
    else:
        ahc.add(item.strip("() "))

# the machine-readable absence list: the ABSENT-NAMES line and its
# "--   " continuation lines
absent = set()
lines = src.split("\n")
for i, l in enumerate(lines):
    if l.startswith("-- ABSENT-NAMES:"):
        txt = l[len("-- ABSENT-NAMES:"):]
        j = i + 1
        while j < len(lines) and lines[j].startswith("--   "):
            txt += " " + lines[j][2:]
            j += 1
        absent = set(re.findall(r"[A-Za-z_][\w']*", txt))
        break

missing = sorted(ghc - ahc - absent)
extra = sorted(ahc - ghc)
stale = sorted(absent & ahc)
bad = False
if missing:
    print("GHC's Prelude exports, ours does not (and not documented absent):", *missing); bad = True
if extra:
    print("ours exports, GHC's Prelude does not:", *extra); bad = True
if stale:
    print("documented absent but exported:", *stale); bad = True
if bad:
    sys.exit(1)
print("prelude exports ok: %d names, %d documented absent" % (len(ahc), len(absent)))
PY
rc=$?
rm -f "$out"
exit $rc
