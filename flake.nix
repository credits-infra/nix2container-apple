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

          baseFiles = pkgs.runCommand "base-files" { } ''
            mkdir -p $out/bin $out/usr/bin $out/tmp $out/workspace $out/go $out/npm-cache $out/root
            ln -s ${pkgs.coreutils}/bin/env $out/usr/bin/env
            ln -sf ${pkgs.bashInteractive}/bin/bash $out/bin/sh
          '';

          rootEnv = pkgs.buildEnv {
            name = "root-env";
            paths = devTools;
            pathsToLink = [ "/bin" "/etc" "/usr" "/share" ];
          };
        in
        n2c.buildImage {
          name = "ghcr.io/credits-infra/nix2container-apple";
          tag = "latest";

          copyToRoot = [
            baseFiles
            rootEnv
            pkgs.dockerTools.fakeNss
          ];

          perms = [
            {
              path = baseFiles;
              regex = "^/tmp";
              mode = "1777";
            }
            {
              path = baseFiles;
              regex = "^/(workspace|go|npm-cache|root)";
              mode = "0777";
            }
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
