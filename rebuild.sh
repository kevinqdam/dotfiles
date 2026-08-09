#!/usr/bin/env bash
set -e

cd ~/.dotfiles
git add .

echo "Building the Nix system..."
nix build .#darwinConfigurations.macbook.system

echo "Applying the system configuration..."
sudo ./result/sw/bin/darwin-rebuild switch --flake .#macbook

# Keep the upstream Firstmate checkout current after the system is applied.
./setup-harnesses
