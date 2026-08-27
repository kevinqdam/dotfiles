#!/usr/bin/env bash
set -e

if [ "$#" -gt 1 ]; then
  printf 'usage: %s [--upgrade]\n' "$0" >&2
  exit 2
fi

case "${1:-}" in
  "") upgrade=false ;;
  --upgrade) upgrade=true ;;
  *)
    printf 'usage: %s [--upgrade]\n' "$0" >&2
    exit 2
    ;;
esac

cd ~/.dotfiles

if [ "$upgrade" = true ]; then
  echo "Upgrading the targeted Homebrew packages..."
  ./agents/converge-firstmate-homebrew \
    /opt/homebrew/bin/brew \
    "$(id -un)"
fi

git add .

echo "Building the Nix system..."
nix build .#darwinConfigurations.macbook.system

echo "Applying the system configuration..."
sudo ./result/sw/bin/darwin-rebuild switch --flake .#macbook

# Keep the upstream Firstmate checkout current after the system is applied.
./agents/setup-harnesses
