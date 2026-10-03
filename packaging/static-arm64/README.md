# Static aarch64 build and Debian package

This directory builds Eclipse Mosquitto as **fully static aarch64 binaries**
(musl libc, OpenSSL built in) and packages them as a `.deb`. The package
installs and runs like the official Debian bookworm `mosquitto` package.

The main use case is a Raspberry Pi 5, or any other arm64 system running
Debian 12 (bookworm) / Raspberry Pi OS, that should run a current Mosquitto
release without depending on the distribution's (older) shared libraries.

## Building

Requirements: [Nix](https://nixos.org/download) on an x86_64 or aarch64 Linux
host. Nixpkgs is pinned in `shell.nix`, so all dependencies are fetched in
fixed versions.

```sh
make static-arm64-deb
# or: packaging/static-arm64/build.sh
```

Without a local Nix installation you can build in Docker:

```sh
docker run --rm -v "$PWD":/src -w /src nixos/nix \
    nix-shell packaging/static-arm64/shell.nix --run packaging/static-arm64/build.sh
```

The output goes to `build/static-arm64/`:

| File                                  | Content                         |
|---------------------------------------|---------------------------------|
| `mosquitto_<version>-0static1_arm64.deb` | Debian package                |
| `mosquitto-<version>-arm64-static.tar.gz` | Stripped static binaries     |
| `SHA256SUMS`                          | Checksums of the two files above |

The build fails if any of the binaries ends up dynamically linked.

## Installing

```sh
sudo dpkg -i mosquitto_2.1.2-0static1_arm64.deb
sudo apt-mark hold mosquitto   # keep apt from replacing it with Debian's 2.0.x
```

The only dependency is `adduser`, which is part of every Debian base system.
The package replaces an installed Debian `mosquitto` and `mosquitto-clients`.
Your files in `/etc/mosquitto/conf.d/` and the persistence database in
`/var/lib/mosquitto/` are kept. `libmosquitto1` is not touched, because other
packages may depend on it.

To check that a binary is static: `ldd /usr/sbin/mosquitto` prints
`not a dynamic executable`.

## What is installed

The layout follows the Debian bookworm package `mosquitto 2.0.11-1.2+deb12u2`.
The configuration files, init script, systemd unit, logrotate config and
maintainer scripts in `debian/` are taken unchanged from that package.

| Path | |
|------|-|
| `/usr/sbin/mosquitto` | Broker |
| `/usr/bin/mosquitto_{pub,sub,rr}` | Clients (Debian: package `mosquitto-clients`) |
| `/usr/bin/mosquitto_{passwd,ctrl}` | Tools as in Debian |
| `/usr/bin/mosquitto_{signal,db_dump}` | Additional tools from 2.1 |
| `/etc/mosquitto/` | Debian configuration (`mosquitto.conf`, `conf.d/`, examples) |
| `/lib/systemd/system/mosquitto.service` | Debian unit, `Type=notify` |
| `/etc/init.d/mosquitto`, `/etc/logrotate.d/mosquitto` | As in Debian |
| `/var/lib/mosquitto/`, `/var/log/mosquitto/` | Owned by the `mosquitto` system user, created by `postinst` |

The installed size is about 35 MB, because every binary contains its own
copy of OpenSSL.

## Differences from the Debian package

- **No plugins.** A static musl binary cannot load shared objects, so
  `mosquitto_dynamic_security.so` and other plugins are not part of the
  package and cannot be loaded with `plugin`. The built-in `acl_file` and
  `password_file` options work.
- **No libwrap** (TCP wrappers, `/etc/hosts.allow`) and **no DLT** logging.
- **Name resolution** uses musl: `/etc/hosts` and DNS work, NSS modules do
  not. In particular, mDNS names (`*.local`) cannot be resolved.
- **HTTP API without TLS.** libmicrohttpd is built without gnutls, so an
  `http_api` listener cannot use a certificate.
- **No man pages** (`WITH_DOCS=no`).
- **`mosquitto_ctrl`** has no interactive shell (`WITH_EDITLINE=no`).

TLS for MQTT, websockets and bridges is fully supported. OpenSSL is
configured with the Debian `OPENSSLDIR` (`/usr/lib/ssl`), so the system CA
certificates are found as usual.

## Upgrading from Debian's 2.0.x

These are changes in Mosquitto 2.1 itself, not in this build, but they show
up when replacing the Debian package:

- `acl_file` and `password_file` must not be **symlinks**. They are opened
  with `O_NOFOLLOW` and the broker fails with `Unable to open acl_file`.
  Point the option to the real file, or set
  `MOSQUITTO_UNSAFE_ALLOW_SYMLINKS=1` in a systemd drop-in
  (`systemctl edit mosquitto`, `[Service]`, `Environment=...`).
- These files are read after dropping privileges and must be readable by
  the `mosquitto` user.
- Invalid lines in `acl_file`/`password_file` are now an error.
- `max_packet_size` defaults to 2,000,000 bytes.

See `ChangeLog.txt` for the full list.

## How it works

- `shell.nix`: pinned Nix cross toolchain
  (`pkgsCross.aarch64-multiplatform.pkgsStatic`) with static OpenSSL, cJSON,
  SQLite and libmicrohttpd.
- `build.sh`: copies the source tree to `build/static-arm64/src`, builds with
  the regular Makefiles (`WITH_SHARED_LIBRARIES=no WITH_STATIC_LIBRARIES=yes
  LDFLAGS=-static`), checks the binaries and assembles the package.
- `sdshim/`: a minimal static `sd_notify()` implementation. It lets the broker
  be built with `WITH_SYSTEMD=yes` without libsystemd, so the Debian unit with
  `Type=notify` (and the systemd watchdog) works.

Besides the files in this directory, the branch contains two small fixes to
the build system. They are needed for static linking with the Makefiles:

- `config.mk`: link `-lssl -lcrypto` after `libmosquitto_common`, which uses
  OpenSSL.
- `apps/mosquitto_ctrl/Makefile`: link `-lssl` before `-lcrypto`.

With shared libraries the order does not matter, so these fixes do not change
regular builds.

## Testing

Tested with the 2.1.2 package in a Debian 12 arm64 root filesystem (under
qemu-user):

- installation with `dpkg -i` on a fresh system and as an upgrade over the
  official `mosquitto` and `mosquitto-clients` packages
- broker started with the unchanged Debian `/etc/mosquitto/mosquitto.conf`:
  PID file, log file, privilege drop to `mosquitto`, persistence, publish and
  subscribe and retained messages behave like the official package
- systemd readiness notification with `Type=notify`

Not tested yet: a full boot with systemd on a real Raspberry Pi 5.
