#!/usr/bin/env bash
# Behavioral contract for Pi's documented external-editor environment fallback.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

fail() {
  printf 'pi-editor.test.sh: %s\n' "$*" >&2
  exit 1
}

session_variables=$(nix eval --impure --json \
  'path:.#darwinConfigurations.macbook.config.home-manager.users.kevindam.home.sessionVariables')
jq -e 'has("VISUAL") | not' <<<"$session_variables" >/dev/null \
  || fail 'Home Manager still exports a global VISUAL editor'
jq -e 'has("EDITOR") | not' <<<"$session_variables" >/dev/null \
  || fail 'Home Manager still exports a global EDITOR editor'

TMP=$(mktemp -d "${TMPDIR:-/tmp}/pi-editor-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
fake_pi="$TMP/pi-target"
cat > "$fake_pi" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${VISUAL-unset}" "${EDITOR-unset}" "$#"
printf '<%s>\n' "$@"
EOF
chmod +x "$fake_pi"

wrapper=$(FAKE_PI="$fake_pi" nix build --impure --no-link --print-out-paths --expr '
  let
    flake = builtins.getFlake (toString ./.);
    pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  in import ./nix/pi-with-vim.nix {
    inherit pkgs;
    piExecutable = builtins.getEnv "FAKE_PI";
  }
')
output=$(VISUAL=emacs EDITOR=nano "$wrapper/bin/pi" alpha 'two words')
[ "$output" = 'vim
vim
2
<alpha>
<two words>' ] || fail 'managed Pi launcher did not scope Vim or preserve arguments'

printf 'ok - Vim is scoped to the managed Pi launcher\n'
