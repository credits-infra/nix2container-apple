#!/usr/bin/env bash
set -euo pipefail

# Check for Apple container CLI
if ! command -v container >/dev/null 2>&1; then
  echo "Error: 'container' command not found. Please install apple/container first." >&2
  exit 1
fi

# Check if container system service is running
if ! container system status >/dev/null 2>&1; then
  echo "apple/container system daemon is not running."
  echo "Starting container system service..."
  container system start
fi

# Configuration & Defaults
IMAGE="${IMAGE:-ghcr.io/credits-infra/nix2container-apple:aarch64-latest}"
HOST_GO_DIR="${HOST_GO_DIR:-$HOME/go}"
HOST_NPM_DIR="${HOST_NPM_DIR:-$HOME/.npm}"

# Ensure host-side cache directories exist
mkdir -p "$HOST_GO_DIR" "$HOST_NPM_DIR"

RUN_ARGS=(
  --rm
  --read-only
  --tmpfs /tmp
  -v "$(pwd):/workspace"
  -v "$HOST_GO_DIR:/go"
  -v "$HOST_NPM_DIR:/npm-cache"
  -w /workspace
)

# Run interactive shell if no command is specified
if [ $# -eq 0 ]; then
  echo "==> Entering immutable container environment ($IMAGE)..."
  echo "    Rootfs is read-only. External mounts: $(pwd) -> /workspace, $HOST_GO_DIR -> /go"
  exec container run -it "${RUN_ARGS[@]}" "$IMAGE"
else
  # Run user-supplied command via bash entrypoint
  if [ -t 0 ]; then
    exec container run -it "${RUN_ARGS[@]}" "$IMAGE" -c "$*"
  else
    exec container run "${RUN_ARGS[@]}" "$IMAGE" -c "$*"
  fi
fi
