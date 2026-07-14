#!/bin/bash
# Actual Budget Service Setup
set -e
echo "Setting up Actual Budget..."
# Check for node
if ! command -v node &> /dev/null; then
    echo "Node.js not found. Please install Node.js."
    exit 1
fi
npm install @actual-app/api
echo "Setup complete. Run server with your local config."
