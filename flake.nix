{
  description = "Modular, immutable builder and dev environment OCI images for apple/container";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nix2container }:
    let
      supportedSystems = [ "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Core container builder function powered by the Nix module system
      mkContainer = system: modules:
        let
          pkgs = import nixpkgs { inherit system; };
          n2c = nix2container.packages.${system}.nix2container;

          eval = pkgs.lib.evalModules {
            modules = modules ++ [
              {
                _module.args = {
                  inherit pkgs system;
                };
              }
            ];
          };
          cfg = eval.config;

          extraDirs = pkgs.runCommand "extra-dirs" { } ''
            mkdir -p $out/tmp $out/workspace $out/go $out/npm-cache $out/root
          '';

          rootEnv = pkgs.buildEnv {
            name = "${cfg.name}-root";
            paths = cfg.packages ++ [
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
          name = cfg.imageName;
          tag = cfg.tag;

          copyToRoot = [
            rootEnv
          ];

          config = {
            Env = cfg.env;
            WorkingDir = cfg.workingDir;
            Entrypoint = cfg.entrypoint;
          };
        };
    in
    {
      # Export modular builder for external flakes or reuse
      lib.mkContainer = mkContainer;

      # Predefined container images
      packages = forAllSystems (system: {
        # Base builder image with core POSIX & build toolchain
        base = mkContainer system [
          ./modules/base.nix
        ];

        # Specialized builder for helixblast (Go + Node + BLAST+)
        helixblast-builder = mkContainer system [
          ./modules/helixblast.nix
        ];

        # Default image
        default = self.packages.${system}.helixblast-builder;
      });
    };
}
