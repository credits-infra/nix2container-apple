# nix2container-apple

Immutable, hermetic, and minimal OCI development and build containers for [Apple Container (`apple/container`)](https://github.com/apple/container), built with [nix2container](https://github.com/nlewo/nix2container).

---

## 💡 Core Philosophy: Package Management Belongs Outside the Container

Traditional container development environments rely on mutating package managers (`apt`, `apk`, `dnf`) inside the container:
- **Non-reproducible**: `apt-get install` at different dates fetches different package versions.
- **State Drift**: Ad-hoc package installations inside running containers mutate state, breaking consistency across machines.
- **Attack Surface**: Package managers, doc files, caches, and unused binaries bloat the rootfs.

**With Nix & `apple/container`:**
1. **Package management is performed strictly outside the container** during build time via declarative Nix expressions (`flake.nix` + `flake.lock`).
2. **The container rootfs is 100% immutable and read-only**: only the minimal dependency closure lives in the container. No package manager inside.
3. **State is externalized**: mutable states like `~/go` (Go module cache / build cache), `~/.npm` (NPM cache), and source trees are bind-mounted from the macOS host.
4. **Native Apple Silicon Speed**: `apple/container` spins up lightweight Linux virtual machines directly via macOS `Virtualization.framework`, natively running `aarch64-linux` containers.

---

## 🏗️ Architecture: Multi-Package & Role-based Containers

This repository publishes **independent OCI packages** with native `:latest` tags under `ghcr.io/credits-infra/`:

| Package | Role | Contents | Target Usage |
| :--- | :--- | :--- | :--- |
| **`ghcr.io/credits-infra/base-dev`** | Base DevShell / Builder | POSIX core, Bash, Git, Make, GCC, SSL certs | Base foundation for all builder modules |
| **`ghcr.io/credits-infra/helixblast-dev`** | Specialized DevShell / Builder | `base-dev` + Go 1.26, Node 24, BLAST+, golangci-lint | Development, build, and tests for helixblast |
| *(Future)* **`ghcr.io/credits-infra/helixblast`** | Production Release Runtime | Minimal distroless, compiled binaries only | Zero-build-tool production release deployment |

```
+-------------------------------------------------------------+
| External Build Stage (GitHub Actions)                       |
|   flake.nix (Evaluates modules) -> nix2container            |
|   ├── modules/base.nix           -> base-dev:latest         |
|   ├── modules/helixblast-dev.nix -> helixblast-dev:latest   |
|   └── modules/<name>-dev.nix     -> <name>-dev:latest       |
|   Architectures: aarch64-linux (Apple Silicon), x86_64-linux|
+-------------------------------------------------------------+
                            │
                            │ container image pull / run
                            ▼
+-------------------------------------------------------------+
| macOS Host (apple/container)                                |
|   Immutable Rootfs (--read-only)                            |
|   Mounts:                                                   |
|     -v $(pwd):/workspace                                    |
|     -v $HOME/go:/go                                         |
|     -v $HOME/.npm:/npm-cache                                |
+-------------------------------------------------------------+
```

---

## 🧩 Zero-Maintenance Modular Architecture

All container definitions use the **Nix module system** (`lib.evalModules`). Both `flake.nix` and GitHub Actions CI automatically discover all non-base module files in `modules/`.

### Adding a New Container (Single Step!)

To add a new devShell / builder container, **simply create a new file** `modules/<name>-dev.nix`:

```nix
# modules/rust-dev.nix
{ pkgs, ... }:

{
  imports = [
    ./base.nix
  ];

  name = "rust-dev";

  packages = with pkgs; [
    rustc
    cargo
    clippy
    rust-analyzer
  ];

  env = [
    "CARGO_HOME=/cargo"
    "RUSTUP_HOME=/rustup"
  ];
}
```

That's it!
- `flake.nix` automatically registers `packages.<system>.rust-dev`.
- GitHub Actions CI dynamically generates a matrix build on native ARM64 and x86_64 runners.
- The new package `ghcr.io/credits-infra/rust-dev:latest` is automatically built and pushed.
- You don't need to touch `flake.nix` or any GitHub Actions YAML files!

### Customizing or Overriding Base Dependencies

Modules inherit `basePackages` (POSIX tools, GCC, Make, Git, SSL certs) and `baseEnv` by default. If a specialized module needs to completely replace or customize the base toolchain (e.g. replacing GNU tools with Busybox or changing default PATH):

```nix
{ lib, pkgs, ... }:

{
  imports = [ ./base.nix ];
  name = "minimal-dev";

  # Completely override the base packages using lib.mkForce
  basePackages = lib.mkForce (with pkgs; [ busybox ]);

  # Completely override the base environment variables
  baseEnv = lib.mkForce [ "PATH=/bin" "USER=root" ];
}
```

### Intelligent Multi-Layer Architecture & Layer Sharing

Images are constructed using `nix2container`'s native layer abstraction to maximize reuse across different builder environments:

1. **Shared Base Layer (`baseLayer`)**:
   - Encapsulates foundational POSIX tools, GCC, Make, Git, SSL certificates, and root directory skeletons.
   - Built with `n2c.buildLayer` into a standalone, reproducible layer derivation.
   - **Cross-module deduplication**: All builder modules (e.g., `helixblast-dev`, `rust-dev`, `python-dev`) share the exact same base layer digest. GHCR skips uploading it on new images, and local clients skip re-downloading the ~300MB base layer when switching between dev environments.

2. **Application / Toolchain Layer (`packages`)**:
   - Automatically excludes any store paths already present in the parent base layer.
   - Leverages `maxLayers` (default: 10) to automatically partition large toolchains (like Go, Node.js, BLAST+) according to store path reference popularity, optimizing incremental caching when upgrading individual tools.

3. **Custom Intermediate Layers (`layers`)**:
   - Modules can define custom intermediate layers via `layers = [ ... ]` (e.g., shared language runtimes) to insert between the base layer and top-level packages.

---

## ⚙️ Automated Maintenance & Resource Optimization

1. **Multi-Arch OCI Manifest Index**: GitHub Actions uses `docker buildx imagetools` to merge `aarch64` and `x86_64` images into a single multi-platform `:latest` index. Apple Silicon automatically pulls `aarch64`; Intel/CI pulls `x86_64`.
2. **Path-Filtered CI Triggering**: Documentation-only commits (`**.md`, `docs/**`, `.gitignore`, `LICENSE*`) automatically bypass CI to avoid wasting runner compute hours.
3. **Dynamic Matrix Build**: Only active non-base container modules are compiled, isolating failures and maximizing build parallelism.
4. **Automated Package Pruning**: A scheduled workflow periodically cleans up outdated commit-hash revisions while safeguarding `latest` and `*-latest` tags.

---

## 🚀 Quick Start with apple/container

### Prerequisites

1. Install and start Apple's `container` runtime:
   ```bash
   container system start
   ```

2. Authenticate with GitHub Container Registry (if using private images):
   ```bash
   container registry login ghcr.io
   ```

### Running with `apple-run.sh` CLI

`apple-run.sh` is a flexible launcher that handles volume mapping, read-only rootfs enforcement, and safe argument passing:

```bash
# 1. Enter default interactive devShell (helixblast-dev:latest)
./scripts/apple-run.sh

# 2. Run from anywhere targeting a specific project directory (-C / --dir)
./scripts/apple-run.sh -C /path/to/project make build

# 3. Select a different container package
./scripts/apple-run.sh -p base-dev gcc --version

# 4. Execute build or test commands safely (preserving quotes and spaces)
./scripts/apple-run.sh make build
./scripts/apple-run.sh go test -run "Test.*" ./internal/...

# 5. Run with writeable rootfs for debugging
./scripts/apple-run.sh --rw bash

# 6. Run with Rosetta 2 translation for x86_64 images (automatically selects amd64 variant)
./scripts/apple-run.sh --rosetta go version
./scripts/apple-run.sh --list
```

---

## 🧪 Verified Example: EndCredits/helixblast

This builder container has been tested and verified with [`EndCredits/helixblast`](https://github.com/EndCredits/helixblast), a modern full-stack bioinformatics application requiring Go, Node.js (Vite + React), and NCBI BLAST+:

```bash
# Clone helixblast
git clone git@github.com:EndCredits/helixblast.git
cd helixblast

# 1. Build React frontend & all Go binaries inside immutable container
/path/to/nix2container-apple/scripts/apple-run.sh make build

# 2. Run test suite
/path/to/nix2container-apple/scripts/apple-run.sh go test ./internal/...
```

All build artifacts (`helixblast`, `helixblast-index`, `helixblast-prepare`) are compiled to native `linux/arm64` ELF binaries, written directly into the mounted project directory on the macOS host, with Go module and npm caching shared seamlessly with the host.

