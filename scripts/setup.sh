#!/bin/bash
# Actual Budget Service Setup
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
echo "Setting up Actual Budget..."
# Check for node
if ! command -v node &> /dev/null; then
    echo "Node.js not found. Please install Node.js."
    exit 1
fi
export COREPACK_HOME="$PWD/.cache/corepack"
corepack yarn install --frozen-lockfile
echo "Setup complete. Run server with your local config."
