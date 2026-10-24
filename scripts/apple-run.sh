#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: apple-run.sh [OPTIONS] [--] [COMMAND [ARGS...]]

A flexible runner for Apple Container (apple/container) with immutable rootfs
and host cache directory mapping.

Options:
  -p, --package <name>    Package name under ghcr.io/credits-infra/ (default: helixblast-dev)
  -i, --image <ref>       Full container image reference (overrides -p and -t)
  -t, --tag <tag>         Image tag (default: latest)
  --rosetta               Enable Rosetta 2 translation in guest VM (for x86_64 images)
  --rw, --writeable       Run container with writeable rootfs (default: read-only)
  -v, --volume <mount>    Additional volume mount in host:container format (repeatable)
  -e, --env <key=val>     Additional environment variable (repeatable)
  -w, --workdir <dir>     Working directory inside container (default: /workspace)
  --list                  List locally cached container images and exit
  -h, --help              Show this help message and exit

Examples:
  # Enter interactive shell in default helixblast-dev environment
  ./scripts/apple-run.sh

  # Run make build in helixblast-dev
  ./scripts/apple-run.sh make build

  # Run a command with complex arguments and quotes
  ./scripts/apple-run.sh go test -run "Test.*" ./internal/...

  # Run base-dev environment
  ./scripts/apple-run.sh -p base-dev gcc --version

  # Run with writeable rootfs for debugging
  ./scripts/apple-run.sh --rw bash
EOF
  exit 0
}

# Check for Apple container CLI
if ! command -v container >/dev/null 2>&1; then
  echo "Error: 'container' command not found. Please install apple/container first." >&2
  exit 1
fi

# Check if container system service is running
if ! container system status >/dev/null 2>&1; then
  echo "apple/container system daemon is not running. Starting..."
  container system start
fi

# Defaults
REGISTRY="ghcr.io/credits-infra"
PACKAGE="${PACKAGE:-helixblast-dev}"
TAG="latest"
IMAGE_OVERRIDE=""
READ_ONLY=true
USE_ROSETTA=false
WORKDIR="/workspace"
HOST_GO_DIR="${HOST_GO_DIR:-$HOME/go}"
HOST_NPM_DIR="${HOST_NPM_DIR:-$HOME/.npm}"
EXTRA_VOLUMES=()
EXTRA_ENVS=()

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    --list)
      exec container image list
      ;;
    -p|--package)
      PACKAGE="$2"
      shift 2
      ;;
    -t|--tag)
      TAG="$2"
      shift 2
      ;;
    -i|--image)
      IMAGE_OVERRIDE="$2"
      shift 2
      ;;
    --rw|--writeable)
      READ_ONLY=false
      shift
      ;;
    --rosetta)
      USE_ROSETTA=true
      shift
      ;;
    -v|--volume)
      EXTRA_VOLUMES+=("-v" "$2")
      shift 2
      ;;
    -e|--env)
      EXTRA_ENVS+=("-e" "$2")
      shift 2
      ;;
    -w|--workdir)
      WORKDIR="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Run '$0 --help' for usage." >&2
      exit 1
      ;;
    *)
      # First non-flag argument starts the command
      break
      ;;
  esac
done

# Resolve final image reference
if [[ -n "$IMAGE_OVERRIDE" ]]; then
  IMAGE="$IMAGE_OVERRIDE"
else
  IMAGE="${REGISTRY}/${PACKAGE}:${TAG}"
fi

# Ensure host-side cache directories exist
mkdir -p "$HOST_GO_DIR" "$HOST_NPM_DIR"

# Assemble container options
CONTAINER_ARGS=(
  --rm
  --tmpfs /tmp
  -v "$(pwd):/workspace"
  -v "$HOST_GO_DIR:/go"
  -v "$HOST_NPM_DIR:/npm-cache"
  -w "$WORKDIR"
)

if [[ "$READ_ONLY" == true ]]; then
  CONTAINER_ARGS+=(--read-only)
fi

if [[ "$USE_ROSETTA" == true ]]; then
  CONTAINER_ARGS+=(--rosetta)
fi

if [[ ${#EXTRA_VOLUMES[@]} -gt 0 ]]; then
  CONTAINER_ARGS+=("${EXTRA_VOLUMES[@]}")
fi

if [[ ${#EXTRA_ENVS[@]} -gt 0 ]]; then
  CONTAINER_ARGS+=("${EXTRA_ENVS[@]}")
fi

if [ -t 0 ]; then
  TTY_FLAGS=(-it)
else
  TTY_FLAGS=()
fi

# Execute container
if [ $# -eq 0 ]; then
  echo "==> Entering immutable container environment ($IMAGE)..."
  echo "    Working dir: $WORKDIR | Read-only rootfs: $READ_ONLY"
  exec container run "${TTY_FLAGS[@]}" "${CONTAINER_ARGS[@]}" "$IMAGE"
else
  # Use bash -c '"$@"' bash [ARGS...] to safely preserve spaces, quotes, and array elements
  exec container run "${TTY_FLAGS[@]}" "${CONTAINER_ARGS[@]}" "$IMAGE" -c '"$@"' bash "$@"
fi
