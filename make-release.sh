#!/bin/sh
# Package a lizard-ex release tarball.
#
# Usage:  ./make-release.sh [version]
#
# Produces lizard-ex-<version>.tar.gz plus its .sha256, containing the library,
# the program, the tests, the format specifications and both licences
# (lib/ is BSD, programs/ is GPLv2).
#
# The version is read from lib/lizard_compress.h, so the library version, the
# program banner, the tarball name and the NEWS entry cannot drift apart.  Pass
# the version as an argument to make the check explicit: a mismatch is refused.

set -eu

cd "$(dirname "$0")"

# --- version ---------------------------------------------------------------
hdr_version() { # name of the LIZARD_VERSION_* macro
    sed -n "s/^#define $1[[:space:]]*\([0-9][0-9]*\).*/\1/p" lib/lizard_compress.h | head -1
}
VERSION=$(hdr_version LIZARD_VERSION_MAJOR).$(hdr_version LIZARD_VERSION_MINOR).$(hdr_version LIZARD_VERSION_RELEASE)

if [ -z "$VERSION" ] || [ "$VERSION" = ".." ]; then
    echo "error: cannot read the version from lib/lizard_compress.h" >&2
    exit 1
fi

if [ "$#" -ge 1 ] && [ "$1" != "$VERSION" ]; then
    echo "error: requested $1 but lib/lizard_compress.h says $VERSION" >&2
    echo "       bump the header (and NEWS) before packaging." >&2
    exit 1
fi

# NEWS must describe this version; tagging without an entry is how a release
# ends up with no notes.
if ! head -1 NEWS | grep -qx "lizard-ex v$VERSION"; then
    echo "error: NEWS starts with '$(head -1 NEWS)' but the tree is at v$VERSION" >&2
    exit 1
fi

TARBALL="lizard-ex-$VERSION.tar.gz"
STAGE="lizard-ex-$VERSION"

echo "==> version $VERSION"

# --- tree state ------------------------------------------------------------
if [ -n "$(git status --porcelain)" ]; then
    echo "warning: the working tree has uncommitted changes; the tarball will not"
    echo "         correspond to any commit.  Press Ctrl-C to stop, or wait 5s."
    sleep 5
fi

# --- verify the tree builds and round-trips before packaging ---------------
echo "==> building"
make clean > /dev/null 2>&1 || true
make all > /dev/null

echo "==> smoke test"
( cd tests && make datagen > /dev/null 2>&1 )
( cd tests && ./datagen -g2M | ../programs/lizard -19 | ../programs/lizard -t > /dev/null )
( cd tests && ./datagen -g2M -P99 | ../programs/lizard -20 | ../programs/lizard -t > /dev/null )
( cd tests && ./datagen -g2M -P50 | ../programs/lizard -29 | ../programs/lizard -t > /dev/null )
( cd tests && ./datagen -g2M -P50 | ../programs/lizard -39 | ../programs/lizard -t > /dev/null )
( cd tests && ./datagen -g2M -P50 | ../programs/lizard -49 | ../programs/lizard -t > /dev/null )

echo "==> bounded test suite"
sh tests/test-fast.sh > /dev/null

# --- stage -----------------------------------------------------------------
echo "==> staging"
rm -rf "$STAGE" "$TARBALL" "$TARBALL.sha256"
mkdir -p "$STAGE"

# Only files under version control ship, so build artefacts (the program, the
# test binaries, objects, libraries) cannot leak into the tarball.
git ls-files lib programs tests doc Makefile NEWS README.md CHANGELOG \
    | while IFS= read -r f; do
        mkdir -p "$STAGE/$(dirname "$f")"
        cp "$f" "$STAGE/$f"
    done

# Licences: lib/ is BSD (lib/LICENSE), programs/ is GPLv2 (programs/COPYING).
[ -f lib/LICENSE ] && cp lib/LICENSE "$STAGE/LICENSE.lib"
[ -f programs/COPYING ] && cp programs/COPYING "$STAGE/COPYING.programs"

# --- checksum --------------------------------------------------------------
# The paths are the ones inside the tarball, so "tar xzf ... && sha256sum -c"
# verifies the extraction.
find "$STAGE" -type f | LC_ALL=C sort | xargs sha256sum > "$TARBALL.sha256"

# --- package ---------------------------------------------------------------
echo "==> packaging $TARBALL"
# Reproducible archive: the same commit gives the same tarball.  Entries are
# sorted and carry a fixed owner and timestamp, taken from SOURCE_DATE_EPOCH
# or from the commit itself.  Done in Python because macOS ships bsdtar, which
# does not have the GNU tar options that would do it in one line.
EPOCH=${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || date +%s)}
python3 tests/make_archive.py "$STAGE" "$TARBALL" "$EPOCH"
rm -rf "$STAGE"

echo
echo "created: $TARBALL"
echo "sha256 : $(sha256sum "$TARBALL" | cut -d' ' -f1)"
echo
echo "next steps:"
echo "  ( cd . && sha256sum -c $TARBALL.sha256 )"
echo "  git tag v$VERSION && git push origin v$VERSION"
echo "  publish the release; the release workflow attaches the binaries"
