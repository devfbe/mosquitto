# Cross toolchain and static dependencies for a fully static aarch64 build
# (musl libc). nixpkgs is pinned so the build is reproducible.
let
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/774debe7a0d1b496e35677ad955a1011c6ff74f3.tar.gz";
    sha256 = "sha256-nQyFkMR78WP6PiXKkDW2SjqzLf/spQqjRuxRGSbcV8k=";
  };
  p = (import nixpkgs {}).pkgsCross.aarch64-multiplatform.pkgsStatic;

  # Use the Debian OPENSSLDIR, so the system CA store (/etc/ssl/certs via
  # /usr/lib/ssl/certs) is found on the target. Installation still goes to
  # the Nix store.
  openssl = p.openssl.overrideAttrs (o: {
    configureFlags = map (f: if builtins.match "--openssldir=.*" f != null then "--openssldir=/usr/lib/ssl" else f) o.configureFlags
      ++ [ "no-engine" ];
    installFlags = [ "OPENSSLDIR=$(etc)/etc/ssl" "ENGINESDIR=$(out)/lib/engines-3" "MODULESDIR=$(out)/lib/ossl-modules" ];
    doCheck = false;
  });

  # libmicrohttpd (HTTP API) would pull in gnutls for HTTPS; build it without.
  libmicrohttpd = p.libmicrohttpd.overrideAttrs (o: {
    buildInputs = [];
    propagatedBuildInputs = [];
    configureFlags = (o.configureFlags or []) ++ [ "--disable-https" ];
    doCheck = false;
  });
in
p.mkShell {
  nativeBuildInputs = [ p.buildPackages.dpkg p.buildPackages.rsync ];
  buildInputs = [ openssl p.cjson p.sqlite libmicrohttpd ];
}
