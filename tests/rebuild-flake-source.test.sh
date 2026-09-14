#!/usr/bin/env bash
# Verify absolute local Nix flake selection in a linked Git worktree.
set -euo pipefail

if ! command -v nix >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  printf 'skip - linked-worktree Nix source check requires nix and git\n'
  exit 0
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/rebuild-flake-source.XXXXXX")
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT

repo="$TMP/repo"
linked="$TMP/linked-worktree"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.invalid
cat > "$repo/flake.nix" <<'EOF'
{
  outputs = { self }: {
    marker = builtins.readFile ./marker;
  };
}
EOF
printf 'main\n' > "$repo/marker"
git -C "$repo" add flake.nix marker
git -C "$repo" commit -q -m initial
git -C "$repo" worktree add -q -b linked "$linked"
printf 'linked\n' > "$linked/marker"
git -C "$linked" add marker
git -C "$linked" commit -q -m linked-marker

[ -f "$linked/.git" ] || {
  printf 'linked worktree did not use a .git file\n' >&2
  exit 1
}
marker=$(nix eval --offline --no-update-lock-file --no-write-lock-file \
  --raw "$linked#marker")
[ "$marker" = linked ] || {
  printf 'expected linked marker, got %s\n' "$marker" >&2
  exit 1
}

printf 'ok - absolute flake evaluation selects linked Git worktree source\n'
