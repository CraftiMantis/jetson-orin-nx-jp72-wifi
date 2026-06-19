#!/usr/bin/env bash
# Install the build prerequisites (toolchain + matching kernel source).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

require_jp72
log "Installing build prerequisites..."
sudo apt-get update -y
sudo apt-get install -y build-essential bc flex bison libssl-dev zstd "linux-source-${SRC_VER}"
log "Prerequisites installed."
