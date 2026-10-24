{ pkgs, ... }:

{
  imports = [
    ./base.nix
  ];

  name = "helixblast-builder";

  packages = with pkgs; [
    go
    nodejs
    golangci-lint
    blast
  ];

  env = [
    "CGO_ENABLED=0"
    "GOPATH=/go"
    "GOCACHE=/go/cache"
    "NPM_CONFIG_CACHE=/npm-cache"
  ];
}
