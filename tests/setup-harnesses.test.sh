#!/usr/bin/env bash
# Behavioral contract for the private-origin Firstmate checkout updater.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SETUP="$SCRIPT_DIR/agents/setup-harnesses"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/setup-harnesses-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'setup-harnesses.test.sh: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  expected=$1
  actual=$2
  [ "$expected" = "$actual" ] || fail "expected '$expected', got '$actual'"
}

origin="$TMP/origin.git"
upstream="$TMP/upstream.git"
seed="$TMP/seed"
checkout="$TMP/checkout"
git init --bare "$origin" >/dev/null
git init --bare "$upstream" >/dev/null
git init "$seed" >/dev/null
git -C "$seed" config user.name Test
git -C "$seed" config user.email test@example.invalid
printf 'initial\n' > "$seed/README.md"
git -C "$seed" add README.md
git -C "$seed" commit -m initial >/dev/null
git -C "$seed" branch -M main
git -C "$seed" remote add origin "$origin"
git -C "$seed" push -u origin main >/dev/null

run_setup() {
  run_setup_at "$checkout"
}

run_setup_at() {
  root=$1
  FIRSTMATE_ROOT="$root" \
  FIRSTMATE_ORIGIN_URL="$origin" \
  FIRSTMATE_UPSTREAM_URL="$upstream" \
  FIRSTMATE_BRANCH=main \
  "$SETUP" >/dev/null
}

run_setup
[ -f "$checkout/README.md" ] || fail 'fresh checkout was not cloned'
assert_eq "$origin" "$(git -C "$checkout" remote get-url origin)"
assert_eq "$origin" "$(git -C "$checkout" config --get remote.origin.pushurl)"
assert_eq "$upstream" "$(git -C "$checkout" remote get-url upstream)"
assert_eq 'no_push://public-upstream-disabled' "$(git -C "$checkout" config --get remote.upstream.pushurl)"
if git -C "$checkout" push upstream main >/dev/null 2>&1; then
  fail 'public upstream accepted a push'
fi

old_head=$(git -C "$checkout" rev-parse HEAD)
printf 'fast-forward\n' >> "$seed/README.md"
git -C "$seed" add README.md
git -C "$seed" commit -m fast-forward >/dev/null
git -C "$seed" push origin main >/dev/null
run_setup
new_head=$(git -C "$checkout" rev-parse HEAD)
[ "$old_head" != "$new_head" ] || fail 'clean checkout did not fast-forward from private origin'
assert_eq "$(git -C "$seed" rev-parse HEAD)" "$new_head"

printf 'local divergence\n' >> "$checkout/README.md"
git -C "$checkout" add README.md
git -C "$checkout" commit -m local-divergence >/dev/null
local_head=$(git -C "$checkout" rev-parse HEAD)
printf 'remote divergence\n' >> "$seed/README.md"
git -C "$seed" add README.md
git -C "$seed" commit -m remote-divergence >/dev/null
git -C "$seed" push origin main >/dev/null
if run_setup; then
  fail 'diverged checkout was updated instead of refusing'
fi
assert_eq "$local_head" "$(git -C "$checkout" rev-parse HEAD)"

detached_checkout="$TMP/detached-checkout"
git clone --branch main "$origin" "$detached_checkout" >/dev/null
git -C "$detached_checkout" config user.name Test
git -C "$detached_checkout" config user.email test@example.invalid
git -C "$detached_checkout" checkout --detach >/dev/null
printf 'detached commit\n' >> "$detached_checkout/README.md"
git -C "$detached_checkout" add README.md
git -C "$detached_checkout" commit -m detached-commit >/dev/null
detached_head=$(git -C "$detached_checkout" rev-parse HEAD)
if run_setup_at "$detached_checkout"; then
  fail 'detached checkout was updated instead of refusing'
fi
assert_eq "$detached_head" "$(git -C "$detached_checkout" rev-parse HEAD)"
if git -C "$detached_checkout" symbolic-ref --quiet HEAD >/dev/null; then
  fail 'detached checkout was switched to a branch'
fi
git -C "$detached_checkout" cat-file -e "$detached_head^{commit}"

off_target_checkout="$TMP/off-target-checkout"
git clone --branch main "$origin" "$off_target_checkout" >/dev/null
git -C "$off_target_checkout" config user.name Test
git -C "$off_target_checkout" config user.email test@example.invalid
git -C "$off_target_checkout" checkout -b captain-work >/dev/null
printf 'off-target commit\n' >> "$off_target_checkout/README.md"
git -C "$off_target_checkout" add README.md
git -C "$off_target_checkout" commit -m off-target-commit >/dev/null
off_target_head=$(git -C "$off_target_checkout" rev-parse HEAD)
if run_setup_at "$off_target_checkout"; then
  fail 'off-target checkout was updated instead of refusing'
fi
assert_eq 'captain-work' "$(git -C "$off_target_checkout" branch --show-current)"
assert_eq "$off_target_head" "$(git -C "$off_target_checkout" rev-parse HEAD)"
git -C "$off_target_checkout" cat-file -e "$off_target_head^{commit}"

printf 'uncommitted\n' >> "$checkout/README.md"
if run_setup; then
  fail 'dirty checkout was updated instead of refusing'
fi
assert_eq "$local_head" "$(git -C "$checkout" rev-parse HEAD)"

printf 'ok - setup-harnesses clone, read-only upstream, fast-forward, branch, and refusal contracts\n'
