#!/usr/bin/env bash
# Build fully static aarch64 (musl) mosquitto binaries and a Debian package
# that installs like the official Debian bookworm "mosquitto" package.
#
# Usage: packaging/static-arm64/build.sh    (or: make static-arm64-deb)
# Output: build/static-arm64/
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT=${OUT:-$ROOT/build/static-arm64}

# Re-run inside the pinned Nix environment if needed.
if [ -z "${IN_NIX_SHELL:-}" ]; then
	exec nix-shell "$HERE/shell.nix" --run "$(printf '%q' "${BASH_SOURCE[0]}")"
fi

VERSION=$(sed -n 's/^VERSION=//p' "$ROOT/config.mk")
DEB_VERSION=${DEB_VERSION:-$VERSION-0static1}
SRC=$OUT/src
PKG=$OUT/mosquitto_${DEB_VERSION}_arm64

echo "==> Copying source tree to $SRC"
mkdir -p "$OUT"
rsync -a --delete --exclude=/.git --exclude=/build "$ROOT/" "$SRC/"
make -C "$SRC" clean >/dev/null

echo "==> Building sd_notify shim"
mkdir -p "$OUT/sdshim"
$CC -O2 -Wall -Wextra -I"$HERE/sdshim/include" -c "$HERE/sdshim/sd_notify.c" -o "$OUT/sdshim/sd_notify.o"
$AR rcs "$OUT/sdshim/libsystemd.a" "$OUT/sdshim/sd_notify.o"

echo "==> Building mosquitto $VERSION (static, aarch64)"
make -C "$SRC" -j"$(nproc)" \
	CC="$CC" CXX="$CXX" AR="$AR" \
	WITH_SHARED_LIBRARIES=no WITH_STATIC_LIBRARIES=yes \
	WITH_DOCS=no WITH_EDITLINE=no WITH_SYSTEMD=yes \
	CPPFLAGS="-I$HERE/sdshim/include" \
	LDFLAGS="-static -L$OUT/sdshim" \
	CLIENT_STATIC_LDADD="-lssl -lcrypto"

BINS="src/mosquitto client/mosquitto_pub client/mosquitto_sub client/mosquitto_rr
	apps/mosquitto_passwd/mosquitto_passwd apps/mosquitto_ctrl/mosquitto_ctrl
	apps/mosquitto_signal/mosquitto_signal apps/db_dump/mosquitto_db_dump"

echo "==> Checking that all binaries are static"
for b in $BINS; do
	if $READELF -l "$SRC/$b" | grep -q "program interpreter" \
			|| $READELF -d "$SRC/$b" 2>/dev/null | grep -q NEEDED; then
		echo "error: $b is dynamically linked" >&2
		exit 1
	fi
done

echo "==> Assembling Debian package"
rm -rf "$PKG"
mkdir -p "$PKG/DEBIAN" "$PKG/var/lib/mosquitto" "$PKG/var/log/mosquitto"
install -Dm755 "$SRC/src/mosquitto" "$PKG/usr/sbin/mosquitto"
for b in $BINS; do
	[ "$b" = src/mosquitto ] || install -Dm755 "$SRC/$b" "$PKG/usr/bin/$(basename "$b")"
done
$STRIP --strip-unneeded "$PKG/usr/sbin/"* "$PKG/usr/bin/"*

# Configuration, init script, systemd unit and logrotate as in Debian.
cp -a "$HERE/debian/files/." "$PKG/"
cp "$HERE/debian/DEBIAN/"* "$PKG/DEBIAN/"
chmod 755 "$PKG/etc/init.d/mosquitto" "$PKG/DEBIAN/"{preinst,postinst,prerm,postrm}

DOC=$PKG/usr/share/doc/mosquitto
install -Dm644 "$SRC/LICENSE.txt" "$DOC/copyright"
install -Dm644 "$SRC/mosquitto.conf" "$DOC/examples/mosquitto.conf.example"
install -Dm644 "$HERE/README.md" "$DOC/README.static.md"
gzip -9n -c "$SRC/ChangeLog.txt" > "$DOC/changelog.gz"

INSTALLED_SIZE=$(du -sk --exclude=DEBIAN "$PKG" | cut -f1)
sed -e "s/@VERSION@/$DEB_VERSION/" -e "s/@INSTALLED_SIZE@/$INSTALLED_SIZE/" \
	"$HERE/debian/control.in" > "$PKG/DEBIAN/control"
(cd "$PKG" && find . -type f ! -path './DEBIAN/*' ! -path './etc/*' -printf '%P\0' \
	| sort -z | xargs -0 md5sum) > "$PKG/DEBIAN/md5sums"

dpkg-deb --root-owner-group -Zxz --build "$PKG" "$OUT/" >/dev/null

echo "==> Packing binaries"
TARDIR=mosquitto-$VERSION-arm64-static
rm -rf "${OUT:?}/$TARDIR"
mkdir -p "$OUT/$TARDIR"
cp "$PKG/usr/sbin/mosquitto" "$PKG/usr/bin/"* "$OUT/$TARDIR/"
tar -C "$OUT" -czf "$OUT/$TARDIR.tar.gz" "$TARDIR"

(cd "$OUT" && sha256sum "mosquitto_${DEB_VERSION}_arm64.deb" "$TARDIR.tar.gz" > SHA256SUMS)
echo "==> Done:"
sed "s|  |  $OUT/|" "$OUT/SHA256SUMS"
