#!/usr/bin/env bash
# Repo scouting for the breadth milestones (M132's round one,
# M141's round two). NOT a gate: a research tool that does the
# mechanical part of "does AHC compile real code off GitHub" -
# find, filter, clone, build, classify - so the judgement can go
# into the failures, which are the actual deliverable.
#
#   scripts/scout_repos.sh search "sudoku solver"   candidates + why rejected
#   scripts/scout_repos.sh try owner/repo           clone, build, run, classify
#   scripts/scout_repos.sh report                   the table so far
#
# A repo counts only if AHC compiles it AS PUBLISHED, modulo file
# MOVES: AHC resolves imports beside the root file, so a src/+app/
# layout is flattened. Editing a line of Haskell disqualifies it.
set -u
cd "$(dirname "$0")/.."
root=$PWD
work=${SCOUT_DIR:-/tmp/ahc-scout}
mkdir -p "$work"
log="$work/results.tsv"
AHC=$root/bin/ahc
[ -x "$AHC" ] || { echo "build first: alr build --validation" >&2; exit 2; }

# Every module AHC provides, derived from the tree rather than
# listed here, so the filter cannot drift from the library.
ahc_modules() {
  find "$root/lib" -name '*.hs' \
    | sed "s|$root/lib/||; s|\.hs$||; s|/|.|g"
  echo Prelude
}

usage() { sed -n '2,16p' "$0"; exit 2; }

# ---- filter: reject on pragmas or imports outside AHC's set ------
# Prints "OK" or the reason, given a directory of Haskell sources.
filter_dir() {
  local dir=$1 mods hs pragmas imports bad
  mods=$(ahc_modules | sort -u)
  hs=$(find "$dir" -name '*.hs' -not -path '*/dist*' -not -path '*/.stack-work/*' \
       -not -name 'Setup.hs')
  [ -n "$hs" ] || { echo "no .hs files"; return 1; }
  # tr -d '\r' everywhere: a CRLF repo would otherwise leave the
  # carriage return on the module name and every import would look
  # foreign (the filter rejected Data.Char on its first outing).
  # Extensions AHC accepts, always on (M147 and earlier): a repo using
  # only these is a candidate.
  local ok_ext='^(LambdaCase|FlexibleInstances|TypeSynonymInstances|GeneralizedNewtypeDeriving|GeneralisedNewtypeDeriving|InstanceSigs|OverloadedStrings)$'
  pragmas=$(grep -h '{-# *LANGUAGE' $hs 2>/dev/null \
            | sed 's/.*LANGUAGE *//; s/ *#-}.*//' | tr ',' '\n' \
            | tr -d ' \r' | sort -u | grep -v '^$' | grep -Ev "$ok_ext")
  if [ -n "$pragmas" ]; then
    echo "extensions: $(echo $pragmas | tr '\n' ' ')"; return 1
  fi
  # every import must be local (a module the repo defines) or AHC's
  local local_mods
  local_mods=$(grep -h '^module ' $hs 2>/dev/null | awk '{print $2}' \
               | sed 's/(.*//' | tr -d '\r' | sort -u)
  imports=$(grep -h '^ *import ' $hs 2>/dev/null \
            | sed 's/^ *import *//; s/^qualified *//; s/ .*//; s/(.*//' \
            | tr -d '\r' | sort -u | grep -v '^$')
  bad=""
  for m in $imports; do
    echo "$mods" | grep -qx "$m" && continue
    echo "$local_mods" | grep -qx "$m" && continue
    bad="$bad $m"
  done
  [ -n "$bad" ] && { echo "imports:$bad"; return 1; }
  echo OK
}

cmd_search() {
  local q=$1 repo desc
  gh search repos --language=haskell --limit "${SCOUT_LIMIT:-25}" \
     --json fullName,description,stargazersCount "$q" \
    -q '.[] | .fullName + "\t" + ((.stargazersCount|tostring)) + "\t" + (.description // "")' \
  | while IFS=$'\t' read -r repo stars desc; do
      # the file list first: cheap, and rejects most candidates
      local files pragma_hit
      files=$(gh api "repos/$repo/git/trees/HEAD?recursive=1" \
              -q '.tree[].path' 2>/dev/null)
      [ -n "$files" ] || { echo "SKIP  $repo (no tree)"; continue; }
      echo "$files" | grep -q '\.hs$' || { echo "SKIP  $repo (no .hs)"; continue; }
      local n
      n=$(echo "$files" | grep -c '\.hs$')
      [ "$n" -gt 12 ] && { echo "SKIP  $repo ($n modules - too big for a first pass)"; continue; }
      printf 'CAND  %-45s %4s stars  %2s modules  %s\n' "$repo" "$stars" "$n" "$desc"
    done
}

cmd_try() {
  # Two statements on purpose: bash expands every word of a `local`
  # BEFORE it assigns any of them, so $repo would be unset here.
  local repo=$1
  local dir=$work/$(echo "$repo" | tr / _)
  rm -rf "$dir"
  git clone -q --depth 1 "https://github.com/$repo" "$dir" 2>/dev/null \
    || { record "$repo" CLONE-FAIL ""; return; }
  # flatten a src/+app/ layout (a MOVE, not an edit)
  local flat=$dir/_flat
  mkdir -p "$flat"
  # Setup.hs is Cabal's build driver, not part of the program. Reading
  # it made the filter reject every repo with a stock cabal skeleton on
  # its `import Distribution.Simple` - including 2016rshah/sudoku-solver,
  # which round one lists as working. A scout that cannot re-find what
  # round one found is not evidence.
  find "$dir" -name '*.hs' -not -path "$flat/*" -not -path '*/dist*' \
       -not -path '*/.stack-work/*' -not -path '*/test*/*' \
       -not -name 'Setup.hs' \
       -exec cp {} "$flat/" \; 2>/dev/null
  # Data files the program needs but the repo does not ship: anything
  # under $work/files/<owner_repo>/ is copied in after the clone.
  # Input, not an edit - the rule is that no line of HASKELL changes.
  local key
  key=$(echo "$repo" | tr / _)
  if [ -d "$work/files/$key" ]; then
    cp -R "$work/files/$key/." "$dir/" 2>/dev/null
  fi
  local why
  why=$(filter_dir "$flat")
  if [ "$why" != OK ]; then record "$repo" FILTERED "$why"; return; fi
  # the module with main is the root
  local mains main out err lib
  mains=$(grep -l '^main *::\|^main *=' "$flat"/*.hs 2>/dev/null)
  main=$(echo "$mains" | head -1)
  if [ -n "$main" ]; then
    out=$("$AHC" build "$main" "$dir/prog" 2>&1); err=$?
    if [ $err -eq 0 ]; then
      differential "$repo" "$dir" "$main"
    else
      local diag
      diag=$(first_error "$out")
      record "$repo" "$(classify "$diag")" "$(printf '%s' "$diag" | cut -c1-140)"
    fi
    return
  fi
  # No runnable main - plenty of exercise repos are a module of
  # definitions. Library mode still exercises the whole frontend and
  # code generator, which is what round one's last three entries mean
  # by "typechecks and generates C".
  lib=$(ls "$flat"/*.hs | head -1)
  out=$("$AHC" build --lib "$lib" "$dir/prog.a" 2>&1); err=$?
  if [ $err -eq 0 ]; then
    record "$repo" LIB-ONLY "$(basename "$lib") (no main; --lib)"
  else
    local diag
    diag=$(first_error "$out")
    record "$repo" "$(classify "$diag")" "$(printf '%s' "$diag" | cut -c1-140)"
  fi
}

# The diagnostic that decides the class is the first ERROR, not the
# first line: AHC prints warnings (non-exhaustive patterns and the
# like) before them, and classifying on a warning both mislabels the
# repo and hides the failure that actually stopped the build.
first_error() {
  printf '%s' "$1" | grep -m1 ': error:' \
    || printf '%s' "$1" | grep -m1 -v ': warning:' \
    || printf '%s' "$1" | head -1
}

# A build is not the claim; "runs and agrees with GHC" is. Run the
# AHC binary and the GHC binary over the SAME stdin and compare
# stdout+stderr and exit status. macOS has no timeout(1). Anything
# GHC itself refuses is NO-ORACLE, not a failure of AHC.
#
# An interactive program read from /dev/null dies at the first
# getLine, and "both died identically at the prompt" is thin evidence
# that AHC ran it. Drop a transcript at $work/stdin/<owner_repo> and
# BOTH binaries are fed it, so the comparison covers the program's
# actual work. The transcript is part of the claim: it belongs in the
# doc entry beside the command line.
# Run from the repo's own directory: a program that reads a data file
# beside itself (MEAN-stack/Sudoku wants ./sudoku.txt) finds it, and
# both binaries see the same one.
# Wall clock of the last cap, in seconds. Through a FILE, not a
# variable: every caller reads cap's stdout through $(...), which runs
# it in a subshell, so an assignment inside cap would never be seen.
cap_secs() { cat "$work/.cap_secs" 2>/dev/null || echo '?'; }

cap() {
  local t0 t1 rc
  t0=$(perl -MTime::HiRes=time -e 'printf "%.2f", time')
  (cd "$SCOUT_CWD" && perl -e "alarm ${SCOUT_ALARM:-120}; exec @ARGV" \
     "$@" $SCOUT_ARGS <"${SCOUT_STDIN:-/dev/null}" 2>&1)
  rc=$?
  t1=$(perl -MTime::HiRes=time -e 'printf "%.2f", time')
  perl -e "printf '%.2f', $t1 - $t0" > "$work/.cap_secs"
  return $rc
}

stdin_note() {
  [ -n "$SCOUT_ARGS" ] && printf ' %s' "$SCOUT_ARGS"
  [ "$SCOUT_STDIN" = /dev/null ] && return
  printf ' < %s' "$SCOUT_STDIN"
}

differential() {
  local repo=$1 dir=$2 main=$3
  local a_out a_rc g_out g_rc
  local key
  key=$(echo "$repo" | tr / _)
  local SCOUT_STDIN=$work/stdin/$key   # set again: separate function
  [ -f "$SCOUT_STDIN" ] || SCOUT_STDIN=/dev/null
  # Command-line arguments, one line, word-split on purpose: several
  # of these programs do all their work in argv and print nothing
  # without it (tmhedberg/caesar, nlarosa/HaskellRomanNumerals both
  # "agreed" on zero lines of output until they got some).
  local SCOUT_ARGS=""
  [ -f "$work/args/$key" ] && SCOUT_ARGS=$(head -1 "$work/args/$key")
  local SCOUT_CWD=$dir
  # BOTH binaries are named prog, in sibling directories: a program
  # that branches on getProgName (nlarosa/HaskellRomanNumerals picks
  # its conversion that way) would otherwise be asked to do two
  # different jobs and then be blamed for the difference.
  mkdir -p "$dir/.bin.ahc" "$dir/.bin.ghc"
  cp "$dir/prog" "$dir/.bin.ahc/prog"
  a_out=$(cap "$dir/.bin.ahc/prog"); a_rc=$?
  local a_secs; a_secs=$(cap_secs)
  local base
  base=$(basename "$main")
  # AHC takes the root file's `main` as the entry point whatever the
  # module is called; GHC wants a module named Main unless told
  # otherwise. -main-is is the oracle's setup, not an edit to the
  # repo, so a `module TicTacToe where` program still gets compared.
  local modname mainis=()
  modname=$(grep -m1 '^module ' "$dir/_flat/$base" \
            | awk '{print $2}' | sed 's/(.*//' | tr -d ' \r')
  [ -n "$modname" ] && [ "$modname" != Main ] && mainis=(-main-is "$modname")
  if ! (cd "$dir/_flat" && ghc -v0 "${mainis[@]+"${mainis[@]}"}" \
          -o "$dir/.bin.ghc/prog" "$base") >/dev/null 2>&1; then
    record "$repo" NO-ORACLE "$base builds and runs (rc=$a_rc); GHC 9.4.8 will not build it"
    return
  fi
  g_out=$(cap "$dir/.bin.ghc/prog"); g_rc=$?
  local g_secs; g_secs=$(cap_secs)
  # 142 is the alarm. AHC computing the right answer far slower than
  # GHC is a PERFORMANCE result, and calling it DIFFERS would report
  # it as a wrong answer - which is the one thing it is not.
  if [ "$a_rc" = 142 ] && [ "$g_rc" != 142 ]; then
    record "$repo" TIMEOUT \
      "$base$(stdin_note); GHC finished in ${g_secs}s, AHC still running at ${SCOUT_ALARM:-120}s"
    return
  fi
  if [ "$a_out" = "$g_out" ] && [ "$a_rc" = "$g_rc" ]; then
    record "$repo" AGREES \
      "$base -> $dir/prog$(stdin_note); rc=$a_rc, $(printf '%s' "$a_out" | grep -c '' | tr -d ' ') lines identical to GHC (${a_secs}s vs ${g_secs}s)"
  elif [ "$a_rc" = "$g_rc" ] \
       && [ "$(printf '%s' "$a_out" | sed 's|ahc: |PROG: |g')" \
          = "$(printf '%s' "$g_out" | sed 's|prog: |PROG: |g')" ]; then
    # AHC's fatal banner says "ahc:" where GHC says the program's own
    # name. A known gap, recorded as its own outcome rather than
    # normalised away silently - and kept out of DIFFERS, where it
    # would mask a program that computes the wrong answer.
    record "$repo" AGREES-BANNER \
      "$base -> $dir/prog$(stdin_note); rc=$a_rc; identical but for the 'ahc:' fatal prefix"
  else
    printf '%s\n' "$a_out" > "$dir/out.ahc"
    printf '%s\n' "$g_out" > "$dir/out.ghc"
    record "$repo" DIFFERS \
      "$base; ahc rc=$a_rc ghc rc=$g_rc; diff $dir/out.ghc $dir/out.ahc"
  fi
}

# The first diagnostic decides the class; the classes are the gap
# list this milestone exists to produce.
classify() {
  case "$1" in
    *"not in scope"*)            echo RENAME ;;
    *"couldn't match"*|*"no instance"*|*"ambiguous"*) echo TYPE ;;
    *"expected"*|*"parse error"*|*"layout"*) echo PARSE ;;
    *"is not defined"*|*"does not export"*) echo MODULE ;;
    *"clang"*|*"undefined symbol"*) echo LINK ;;
    *) echo OTHER ;;
  esac
}

record() {
  printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >> "$log"
  printf '%-8s %-45s %s\n' "$2" "$1" "${3:-}"
}

cmd_report() {
  [ -f "$log" ] || { echo "nothing tried yet"; return; }
  echo "=== outcomes"; cut -f2 "$log" | sort | uniq -c | sort -rn
  echo; echo "=== detail"; sort -k2 "$log" | awk -F'\t' '{printf "%-8s %-45s %s\n", $2, $1, $3}'
}

case "${1:-}" in
  search) shift; [ $# -ge 1 ] || usage; cmd_search "$*" ;;
  try)    shift; [ $# -ge 1 ] || usage; for r in "$@"; do cmd_try "$r"; done ;;
  report) cmd_report ;;
  *)      usage ;;
esac
