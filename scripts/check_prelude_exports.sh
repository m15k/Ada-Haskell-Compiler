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
# The oracle is GHC 9.4.8: another version's Prelude differs (liftA2, ...).
ver=$("$GHC" --numeric-version 2>/dev/null)
if [ "$ver" != "9.4.8" ]; then
  echo "check_prelude_exports: need GHC 9.4.8, $GHC is '$ver' (set GHC=...)" >&2
  exit 2
fi
out="${TMPDIR:-/tmp}/ahc_browse_prelude.$$"
"$GHC" -e ':browse Prelude' > "$out" 2>/dev/null || { echo "check_prelude_exports: ghc failed" >&2; rm -f "$out"; exit 2; }
python3 - "$out" "${AHC:-./bin/ahc}" <<'PY'
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

# --- class membership: every method GHC's Prelude exports for a class
# must BE a method of AHC's class (not a plain function of the same
# name, which an instance could not define). Checked by asking AHC to
# accept an instance binding each of them: "'m' is not a method of the
# class" is the drift.
import os, subprocess, tempfile
classes = {}      # name -> (kind arity, [methods])
cur = None
kinds = {}
for l in browse:
    m = re.match(r"^type (\S+) :: (.*)$", l)
    if m:
        k = m.group(2)
        k = re.sub(r"\s*->\s*Constraint$", "", k.strip())
        kinds[m.group(1)] = k.count("->") if k.startswith("(") else 0
        continue
    m = re.match(r"^class .*?(?:=>\s*)?(\w+)\b[^=]*where\s*$", l)
    if m and not l.startswith("class ") is False:
        cur = m.group(1)
        # the head's own name: last capitalised word before the variable
        h = re.sub(r"^class\s+(?:.*=>\s*)?", "", l)
        cur = h.split()[0]
        classes[cur] = (kinds.get(cur, 0), [])
        continue
    if cur and l.startswith("  "):
        mm = re.match(r"^\s+(\(?[^\s]+?\)?) ::", l)
        if mm:
            n = mm.group(1)
            if re.match(r"^(\w+\.)+\w", n.strip("()")) and not n.startswith("("):
                continue
            classes[cur][1].append(n)
        continue
    cur = None
bad_members = []
# documented divergences: GHC class methods that are plain functions here
not_methods = set()
for i, l in enumerate(lines_src := src.split("\n")):
    if l.startswith("-- NOT-METHODS:"):
        txt = l[len("-- NOT-METHODS:"):]
        j = i + 1
        while j < len(lines_src) and lines_src[j].startswith("--   "):
            txt += " " + lines_src[j][2:]
            j += 1
        not_methods = set(re.findall(r"[^\s,]+", txt))
        break
ahc_bin = sys.argv[2]
if os.path.exists(ahc_bin):
    lines = ["module Main where"]
    for c, (ar, ms) in sorted(classes.items()):
        ms = [x for x in ms if x.strip("()") not in absent]
        if c in absent or not ms:
            continue
        ty = "T_" + c
        lines.append("data %s%s = %s" % (ty, "".join(" a%d" % i for i in range(ar)), ty))
        lines.append("instance %s %s where" % (c, ty))
        for x in ms:
            lines.append("  %s = undefined" % x)
    lines += ["main :: IO ()", "main = return ()"]
    d = tempfile.mkdtemp()
    f = os.path.join(d, "Main.hs")
    open(f, "w").write("\n".join(lines) + "\n")
    r = subprocess.run([ahc_bin, "check", f], capture_output=True, text=True)
    for l in (r.stderr + r.stdout).split("\n"):
        mm = re.search(r"error: '(.+?)' is not a method of the class", l)
        if mm and mm.group(1).strip("()") not in not_methods:
            bad_members.append(mm.group(1))
else:
    print("check_prelude_exports: %s not built, class membership skipped" % ahc_bin)

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
if bad_members:
    print("exported by GHC as class methods, not methods of AHC's class:", *sorted(set(bad_members))); bad = True
if bad:
    sys.exit(1)
print("prelude exports ok: %d names, %d documented absent" % (len(ahc), len(absent)))
PY
rc=$?
rm -f "$out"
exit $rc
