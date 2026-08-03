#!/usr/bin/env bash
# Build a relocatable release tarball (M131).
#
#   scripts/mkdist.sh [--out DIR]
#
# Produces DIR/ahc-<version>-<os>-<arch>.tar.gz containing a prefix
# tree (bin/ahc + share/ahc/...) plus an install.sh. Because the
# compiler finds its support files relative to its own binary, the
# unpacked tree works IN PLACE - `tar xzf ahc-*.tar.gz && ahc-1.8/bin/ahc
# build Foo.hs` is a complete installation - and `ahc-1.8/install.sh
# --prefix ~/.local` moves it somewhere permanent.
#
# Requires a release build (`alr build --release`); the tarball is
# whatever ./bin/ahc currently is, so build it first.
set -eu
cd "$(dirname "$0")/.."

out=dist
while [ $# -gt 0 ]; do
  case "$1" in
    --out) out="${2:?--out needs a directory}"; shift 2;;
    --out=*) out="${1#--out=}"; shift;;
    -h|--help) sed -n '2,14p' "$0"; exit 0;;
    *) echo "mkdist.sh: unknown argument '$1'" >&2; exit 2;;
  esac
done

[ -x ./bin/ahc ] || {
  echo "mkdist.sh: ./bin/ahc not built (run: alr build --release)" >&2
  exit 2
}

version=$(./bin/ahc --version | awk '{print $2}')
os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)
name="ahc-$version-$os-$arch"

staging=$(mktemp -d); trap 'rm -rf "$staging"' EXIT
root="$staging/$name"

# Reuse install.sh so the tarball layout and the installed layout can
# never drift apart.
scripts/install.sh --prefix "$root" --quiet

# An in-tarball installer that relocates the tree to a real prefix.
cat > "$root/install.sh" <<'RELOC'
#!/usr/bin/env bash
# Relocate this unpacked AHC into a prefix:
#   ./install.sh [--prefix DIR]     (default: /usr/local)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
prefix=/usr/local
case "${1:-}" in
  --prefix) prefix="${2:?--prefix needs a directory}";;
  --prefix=*) prefix="${1#--prefix=}";;
  "") ;;
  *) echo "unknown argument '$1'" >&2; exit 2;;
esac
mkdir -p "$prefix/bin" "$prefix/share"
rm -rf "$prefix/share/ahc"
cp -R "$here/share/ahc" "$prefix/share/ahc"
cp "$here/bin/ahc" "$prefix/bin/ahc"
chmod 755 "$prefix/bin/ahc"
echo "installed $("$prefix/bin/ahc" --version) to $prefix"
RELOC
chmod 755 "$root/install.sh"

mkdir -p "$out"
tar -czf "$out/$name.tar.gz" -C "$staging" "$name"
echo "wrote $out/$name.tar.gz ($(du -h "$out/$name.tar.gz" | cut -f1))"
