#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'rebuild: %s\n' "$*" >&2
  exit 1
}

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

script_source=${BASH_SOURCE[0]}
case "$script_source" in
  /*) ;;
  *) script_source="$PWD/$script_source" ;;
esac

# Resolve the invoked script so both direct clones and ~/.dotfiles symlinks
# select the repository containing this wrapper.
for _ in {1..40}; do
  if [ ! -L "$script_source" ]; then
    break
  fi
  script_dir=$(cd -P "$(dirname "$script_source")" && pwd -P) \
    || fail "cannot resolve script directory: $script_source"
  script_target=$(readlink "$script_source") \
    || fail "cannot read script symlink: $script_source"
  case "$script_target" in
    /*) script_source=$script_target ;;
    *) script_source="$script_dir/$script_target" ;;
  esac
done

[ ! -L "$script_source" ] || fail "too many script symlink levels"
repo_root=$(cd -P "$(dirname "$script_source")" && pwd -P) \
  || fail "cannot resolve repository root"
[ -f "$repo_root/flake.nix" ] || fail "not a dotfiles checkout: $repo_root"
[ -x "$repo_root/agents/setup-harnesses" ] \
  || fail "missing setup-harnesses: $repo_root"
[ -x "$repo_root/agents/converge-firstmate-homebrew" ] \
  || fail "missing Homebrew converger: $repo_root"

cd "$repo_root"

if [ "$upgrade" = true ]; then
  echo "Upgrading the targeted Homebrew packages..."
  ./agents/converge-firstmate-homebrew \
    /opt/homebrew/bin/brew \
    "$(id -un)"
fi

git add .

echo "Building the Nix system..."
nix build "$repo_root#darwinConfigurations.macbook.system"

echo "Applying the system configuration..."
sudo ./result/sw/bin/darwin-rebuild switch --flake "$repo_root#macbook"

# Keep the upstream Firstmate checkout current after the system is applied.
./agents/setup-harnesses
