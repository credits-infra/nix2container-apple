{
  description = "Immutable builder and dev environment OCI image for apple/container";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nix2container }:
    let
      supportedSystems = [ "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      makeBuilderImage = system: pkgs:
        let
          n2c = nix2container.packages.${system}.nix2container;

          devTools = with pkgs; [
            # Shell & Core Utilities
            bashInteractive
            coreutils
            findutils
            gnugrep
            gnused
            gnutar
            gzip
            which
            procps

            # Build tools
            git
            gnumake
            cacert

            # Toolchains for helixblast & modern web/backend
            go
            nodejs
            golangci-lint
            blast
          ];

          extraDirs = pkgs.runCommand "extra-dirs" { } ''
            mkdir -p $out/tmp $out/workspace $out/go $out/npm-cache $out/root
          '';

          rootEnv = pkgs.buildEnv {
            name = "root-env";
            paths = devTools ++ [
              pkgs.dockerTools.usrBinEnv
              pkgs.dockerTools.binSh
              pkgs.dockerTools.fakeNss
              extraDirs
            ];
            pathsToLink = [
              "/bin"
              "/etc"
              "/usr"
              "/share"
              "/tmp"
              "/workspace"
              "/go"
              "/npm-cache"
              "/root"
              "/var"
            ];
          };
        in
        n2c.buildImage {
          name = "ghcr.io/credits-infra/nix2container-apple";
          tag = "latest";

          copyToRoot = [
            rootEnv
          ];


          config = {
            Env = [
              "PATH=/bin:/usr/bin"
              "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
              "SYSTEM_CERTIFICATE_PATH=/etc/ssl/certs/ca-bundle.crt"
              "GOPATH=/go"
              "GOCACHE=/go/cache"
              "NPM_CONFIG_CACHE=/npm-cache"
              "USER=root"
              "HOME=/root"
              "LANG=C.UTF-8"
            ];
            WorkingDir = "/workspace";
            Entrypoint = [ "/bin/bash" ];
          };
        };
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = makeBuilderImage system pkgs;
          helixblast-builder = makeBuilderImage system pkgs;
        });
    };
}
