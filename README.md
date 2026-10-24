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

## 🧩 Modular Architecture: Adding a New Container

All container definitions use the **Nix module system** (`lib.evalModules`), allowing specialized builders to inherit and extend `base.nix` with zero duplication.

### 1. Create a module in `modules/<name>-dev.nix`

```nix
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

### 2. Register the module in `flake.nix`

```nix
packages = forAllSystems (system: {
  base-dev = mkContainer system [ ./modules/base.nix ];
  helixblast-dev = mkContainer system [ ./modules/helixblast-dev.nix ];
  rust-dev = mkContainer system [ ./modules/rust-dev.nix ];
});
```

GitHub Actions will automatically build and publish `ghcr.io/credits-infra/rust-dev:latest` as an independent package!

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

### Running the Immutable Builder / DevShell

Run the prebuilt container as an interactive development shell or builder (defaults to `helixblast-dev:latest`):

```bash
./scripts/apple-run.sh
```

Or switch packages with `PACKAGE=...`:

```bash
PACKAGE=base-dev ./scripts/apple-run.sh
```

Or run arbitrary build / test commands directly:

```bash
./scripts/apple-run.sh make build
./scripts/apple-run.sh go test ./...
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

