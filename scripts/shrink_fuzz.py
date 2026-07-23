#!/usr/bin/env python3
"""Delta-debug shrinker for fuzzer divergences (run_fuzz.sh).

    python3 scripts/shrink_fuzz.py FILE.hs KIND

KIND is the original divergence kind: "mismatch" (outputs differ or
AHC run fails) or "reject" (AHC refuses to compile). The shrinker
repeatedly deletes main-do statements and whole top-level definition
blocks, keeping a deletion only when the program still shows the SAME
kind of divergence (and still compiles under GHC), until no single
deletion survives. Writes FILE.min.hs; run from the repo root.
"""
import os
import subprocess
import sys
import tempfile

RUNGHC = os.environ.get("RUNGHC",
                        os.path.expanduser("~/.ghcup/bin/runghc"))


def outcome(text, workdir):
    """Compile/run under both; return 'illtyped'|'reject'|'mismatch'|'agree'."""
    prog = os.path.join(workdir, "cand.hs")
    exe = os.path.join(workdir, "cand")
    with open(prog, "w") as f:
        f.write(text)
    ghc = subprocess.run([RUNGHC, prog], capture_output=True, timeout=120)
    if ghc.returncode != 0:
        return "illtyped"
    ahc = subprocess.run(["scripts/ahc-build.sh", prog, exe],
                         capture_output=True, timeout=300)
    if ahc.returncode != 0:
        return "reject"
    run = subprocess.run([exe], capture_output=True, timeout=120)
    if run.returncode != 0 or run.stdout != ghc.stdout:
        return "mismatch"
    return "agree"


def candidates(lines):
    """Deletion candidates: single main statements, then def blocks."""
    out = []
    try:
        m = lines.index("main = do")
    except ValueError:
        m = len(lines)
    body = [i for i in range(m + 1, len(lines)) if lines[i].strip()]
    if len(body) > 1:
        for i in body:
            out.append([i])
    # top-level blocks: runs of non-blank lines before "main :: IO ()",
    # skipping the header (imports/data decl stay).
    try:
        end = lines.index("main :: IO ()")
    except ValueError:
        end = len(lines)
    i = 0
    while i < end:
        if lines[i].strip() and (lines[i][0].isalpha()
                                 and lines[i].startswith("f")):
            j = i
            while j < end and lines[j].strip():
                j += 1
            out.append(list(range(i, j)))
            i = j
        else:
            i += 1
    return out


def main():
    if len(sys.argv) != 3 or sys.argv[2] not in ("mismatch", "reject",
                                                 "illtyped"):
        sys.exit(__doc__)
    path, kind = sys.argv[1], sys.argv[2]
    if kind == "illtyped":
        sys.exit(0)  # generator bug: nothing meaningful to shrink
    with open(path) as f:
        lines = f.read().splitlines()
    with tempfile.TemporaryDirectory() as wd:
        if outcome("\n".join(lines) + "\n", wd) != kind:
            print("original does not reproduce; not shrinking")
            sys.exit(1)
        changed = True
        while changed:
            changed = False
            for cand in candidates(lines):
                trial = [l for i, l in enumerate(lines)
                         if i not in set(cand)]
                if outcome("\n".join(trial) + "\n", wd) == kind:
                    lines = trial
                    changed = True
                    break
    out = path[:-3] + ".min.hs"
    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(out)


if __name__ == "__main__":
    main()
