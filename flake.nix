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
            paths = cfg.basePackages ++ cfg.packages ++ [
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
            Env = cfg.baseEnv ++ cfg.env;
            WorkingDir = cfg.workingDir;
            Entrypoint = cfg.entrypoint;
          };
        };
      modulesDir = ./modules;

      # Discover all module definitions in ./modules, excluding base.nix
      moduleFiles = nixpkgs.lib.filterAttrs (name: type:
        type == "regular" &&
        nixpkgs.lib.hasSuffix ".nix" name &&
        name != "base.nix"
      ) (builtins.readDir modulesDir);

      # Dynamically instantiate a container image for each discovered module
      makeModulePackages = system:
        nixpkgs.lib.mapAttrs' (fileName: _:
          let
            moduleName = nixpkgs.lib.removeSuffix ".nix" fileName;
          in
          nixpkgs.lib.nameValuePair moduleName (mkContainer system [ (modulesDir + "/${fileName}") ])
        ) moduleFiles;
    in
    {
      # Export modular builder for external flakes or reuse
      lib.mkContainer = mkContainer;

      # Dynamically discovered container packages
      packages = forAllSystems (system:
        let
          pkgs = makeModulePackages system;
        in
        pkgs // {
          # Default image pointing to helixblast-dev or first discovered package
          default = pkgs.helixblast-dev or (builtins.head (builtins.attrValues pkgs));
          helixblast-builder = pkgs.helixblast-dev or null;
        }
      );
    };
}
