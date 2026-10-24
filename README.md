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

## 🏗️ Architecture

```
+-------------------------------------------------------------+
| External Build Stage (GitHub Actions)                       |
|   flake.nix -> nix2container                                |
|   Outputs: OCI image pushed to ghcr.io                      |
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

### Running the Immutable Builder

Run the prebuilt container as an interactive development shell or builder:

```bash
./scripts/apple-run.sh
```

Or run arbitrary build commands inside:

```bash
./scripts/apple-run.sh make build
./scripts/apple-run.sh go test ./...
```
