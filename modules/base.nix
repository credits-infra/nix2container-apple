{ config, lib, pkgs, ... }:

{
  options = {
    name = lib.mkOption {
      type = lib.types.str;
      default = "base-dev";
      description = "Container image name / identifier";
    };

    registry = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/credits-infra";
      description = "Container registry repository prefix";
    };

    imageName = lib.mkOption {
      type = lib.types.str;
      default = "${config.registry}/${config.name}";
      description = "Full container image repository name";
    };

    tag = lib.mkOption {
      type = lib.types.str;
      default = "latest";
      description = "Container image tag";
    };

    basePackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        # Core POSIX utilities & interactive shell
        bashInteractive
        coreutils
        findutils
        gnugrep
        gnused
        gnutar
        gzip
        which
        procps

        # Essential version control & build utilities
        git
        gnumake
        cacert
        gcc
      ];
      description = "Base POSIX and build utilities (inheritable by all modules, overrideable via lib.mkForce)";
    };

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Module-specific packages to include alongside basePackages";
    };

    baseEnv = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "PATH=/bin:/usr/bin"
        "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
        "SYSTEM_CERTIFICATE_PATH=/etc/ssl/certs/ca-bundle.crt"
        "USER=root"
        "HOME=/root"
        "LANG=C.UTF-8"
      ];
      description = "Base environment variables (inheritable by all modules, overrideable via lib.mkForce)";
    };

    env = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Module-specific environment variables to include alongside baseEnv";
    };

    workingDir = lib.mkOption {
      type = lib.types.str;
      default = "/workspace";
      description = "Default initial working directory inside the container";
    };

    entrypoint = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/bin/bash" ];
      description = "Default entrypoint command";
    };
  };
}
