#!/usr/bin/env bash
# Behavioral contract for the reviewed Pi package convergence helper.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONVERGER="$SCRIPT_DIR/agents/converge-pi-packages"
EFFECTIVE_STATE_CHECKER="$SCRIPT_DIR/agents/pi-effective-package-state.mjs"
INTEGRITY_CHECKER="$SCRIPT_DIR/agents/pi-package-integrity.mjs"
PACKAGE_REPAIRER="$SCRIPT_DIR/agents/pi-repair-package.mjs"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/pi-packages-convergence-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

bin_dir="$TMP/bin"
runtime_bin="$TMP/restricted-bin"
agent_dir="$TMP/agent"
state="$TMP/fake-pi-state"
calls="$TMP/calls"
repair_calls="$TMP/repair-calls"
repair_sdk="$TMP/repair-sdk.mjs"
integrity_contract="$TMP/pi-package-integrity.json"
pi="$bin_dir/pi"
mkdir -p "$bin_dir" "$runtime_bin" "$agent_dir" "$state"

cat > "$integrity_contract" <<'EOF'
{
  "schemaVersion": 1,
  "npmPackages": {
    "npm:@llblab/pi-telegram@0.39.2": {
      "npmIntegrity": "sha512-fixture-telegram",
      "treeSha256": "25ecddc7c6d202dabe1da3ce12d4d886e8fab38550e71e604e5ca48d4cdd532b"
    },
    "npm:pi-web-access@0.25.0": {
      "npmIntegrity": "sha512-fixture-web",
      "treeSha256": "9ff1369cc5bc610933b49498b50818beae6e0bfe8b429cd5611bd55b06b21995"
    },
    "npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6": {
      "npmIntegrity": "sha512-fixture-fast",
      "treeSha256": "381302bb618d2e46a3a273c59346f2be25a9f75a70377f32698cc7e6adac9931"
    }
  }
}
EOF

# Mirror the activation PATH while intentionally masking bare awk. The helper
# must use the stable macOS awk path and only the declared runtime tools.
for runtime_tool in cat jq mkdir node; do
  ln -s "$(command -v "$runtime_tool")" "$runtime_bin/$runtime_tool"
done

installed_pi=$(command -v pi)
installed_pi_real=$(/usr/bin/readlink -f "$installed_pi")
installed_pi_prefix=${installed_pi_real%/bin/pi}
pi_package_manager_sdk="$installed_pi_prefix/libexec/lib/node_modules/@earendil-works/pi-coding-agent/dist/index.js"
[ -f "$pi_package_manager_sdk" ] || {
  printf 'pi-packages-convergence.test.sh: Pi package-manager SDK is unavailable: %s\n' \
    "$pi_package_manager_sdk" >&2
  exit 1
}

cat > "$runtime_bin/git" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = '-C' ] && [ "${3:-}" = 'rev-parse' ] && [ "${4:-}" = 'HEAD' ]; then
  cat "$2/.head"
  exit 0
fi
if [ "${1:-}" = '-C' ] && [ "${3:-}" = 'status' ] && [ "${4:-}" = '--porcelain=v1' ]; then
  [ ! -e "$2/.dirty" ] || printf '%s\n' ' M src/index.ts'
  exit 0
fi
exit 97
EOF
chmod +x "$runtime_bin/git"

cat > "$pi" <<'EOF'
#!/bin/bash
set -euo pipefail
: "${PI_CODING_AGENT_DIR:?}"
: "${STATE:?}"
: "${CALLS:?}"

package_path() {
  case "$1" in
    npm:@llblab/pi-telegram@*)
      printf '%s\n' "$PI_CODING_AGENT_DIR/npm/node_modules/@llblab/pi-telegram"
      ;;
    npm:pi-web-access@*)
      printf '%s\n' "$PI_CODING_AGENT_DIR/npm/node_modules/pi-web-access"
      ;;
    npm:@ryan_nookpi/pi-extension-codex-fast-mode@*)
      printf '%s\n' "$PI_CODING_AGENT_DIR/npm/node_modules/@ryan_nookpi/pi-extension-codex-fast-mode"
      ;;
    git:github.com/algal/pi-openai-server-compaction@*)
      printf '%s\n' "$PI_CODING_AGENT_DIR/git/github.com/algal/pi-openai-server-compaction"
      ;;
    npm:unrelated@*)
      printf '%s\n' "$PI_CODING_AGENT_DIR/npm/node_modules/unrelated"
      ;;
    *)
      return 1
      ;;
  esac
}

write_manifest() {
  package_path=$1
  package_name=$2
  package_version=$3
  extension_entry=${4:-./index.ts}
  extension_file=${extension_entry#./}
  /bin/mkdir -p "$package_path"
  case "$extension_file" in
    */*) /bin/mkdir -p "$package_path/${extension_file%/*}" ;;
  esac
  printf '{"name":"%s","version":"%s","pi":{"extensions":["%s"]}}\n' \
    "$package_name" "$package_version" "$extension_entry" > "$package_path/package.json"
  printf '%s\n' 'export default function extension() {}' > "$package_path/$extension_file"
}

write_telegram_package() {
  package_path=$1
  write_manifest "$package_path" '@llblab/pi-telegram' '0.39.2'
  jq '.pi.skills = ["./skills"]' "$package_path/package.json" > "$STATE/telegram-package.tmp"
  /bin/mv "$STATE/telegram-package.tmp" "$package_path/package.json"
  for skill in generated-control-surface generative-apps telegram-bridge; do
    /bin/mkdir -p "$package_path/skills/$skill"
    printf '%s\n' "# $skill" > "$package_path/skills/$skill/SKILL.md"
  done
}

replace_configured_source() {
  new_source=$1
  case "$new_source" in
    npm:@llblab/pi-telegram@*) identity='npm:@llblab/pi-telegram' ;;
    npm:pi-web-access@*) identity='npm:pi-web-access' ;;
    npm:@ryan_nookpi/pi-extension-codex-fast-mode@*) identity='npm:@ryan_nookpi/pi-extension-codex-fast-mode' ;;
    git:github.com/algal/pi-openai-server-compaction@*) identity='git:github.com/algal/pi-openai-server-compaction' ;;
    *) exit 96 ;;
  esac
  jq --arg source "$new_source" --arg identity "$identity" '
    def source: if type == "string" then . else .source end;
    def same_identity: (source == $identity) or (source | startswith($identity + "@"));
    (.packages // []) as $packages
    | ([range(0; $packages | length) | select($packages[.] | same_identity)] | first) as $index
    | if $index == null then .packages = ($packages + [$source])
      elif .packages[$index] | type == "string" then .packages[$index] = $source
      else .packages[$index].source = $source
      end
  ' "$PI_CODING_AGENT_DIR/settings.json" > "$STATE/settings.tmp"
  /bin/mv "$STATE/settings.tmp" "$PI_CODING_AGENT_DIR/settings.json"
}

remove_configured_source() {
  source_spec=$1
  case "$source_spec" in
    npm:@llblab/pi-telegram@*) identity='npm:@llblab/pi-telegram' ;;
    npm:pi-web-access@*) identity='npm:pi-web-access' ;;
    npm:@ryan_nookpi/pi-extension-codex-fast-mode@*) identity='npm:@ryan_nookpi/pi-extension-codex-fast-mode' ;;
    git:github.com/algal/pi-openai-server-compaction@*) identity='git:github.com/algal/pi-openai-server-compaction' ;;
    *) exit 95 ;;
  esac
  jq --arg identity "$identity" '
    def source: if type == "string" then . else .source end;
    def same_identity: (source == $identity) or (source | startswith($identity + "@"));
    .packages = [(.packages // [])[] | select(same_identity | not)]
  ' "$PI_CODING_AGENT_DIR/settings.json" > "$STATE/settings.tmp"
  /bin/mv "$STATE/settings.tmp" "$PI_CODING_AGENT_DIR/settings.json"
}

case "${1:-}" in
  --version)
    printf '%s\n' "${PI_VERSION:-0.84.3}"
    ;;
  list)
    printf 'User packages:\n'
    if [ -f "$PI_CODING_AGENT_DIR/settings.json" ]; then
      jq -c '.packages[]?' "$PI_CODING_AGENT_DIR/settings.json" | while IFS= read -r package; do
        source_spec=$(printf '%s\n' "$package" | jq -r 'if type == "string" then . else .source end')
        if [ "$(printf '%s\n' "$package" | jq -r type)" = object ]; then
          printf '  %s (filtered)\n' "$source_spec"
        else
          printf '  %s\n' "$source_spec"
        fi
        if path=$(package_path "$source_spec"); then
          printf '    %s\n' "$path"
        fi
      done
    fi
    ;;
  install)
    source_spec=${2:?}
    printf 'install %s\n' "$source_spec" >> "$CALLS"
    case "$source_spec" in
      npm:@llblab/pi-telegram@0.39.2)
        replace_configured_source "$source_spec"
        write_telegram_package "$(package_path "$source_spec")"
        ;;
      npm:pi-web-access@0.25.0)
        replace_configured_source "$source_spec"
        write_manifest "$(package_path "$source_spec")" 'pi-web-access' '0.25.0'
        ;;
      npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6)
        replace_configured_source "$source_spec"
        write_manifest "$(package_path "$source_spec")" '@ryan_nookpi/pi-extension-codex-fast-mode' '0.2.6'
        ;;
      git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055)
        replace_configured_source "$source_spec"
        package_path=$(package_path "$source_spec")
        write_manifest "$package_path" 'pi-openai-server-compaction' '0.1.0' './src/index.ts'
        printf '%s\n' 'c6d593087709e9481223dc6c6c2269b371b5e055' > "$package_path/.head"
        /bin/rm -f "$package_path/.dirty"
        ;;
      *)
        exit 97
        ;;
    esac
    ;;
  remove)
    source_spec=${2:?}
    printf 'remove %s\n' "$source_spec" >> "$CALLS"
    remove_configured_source "$source_spec"
    if installed_path=$(package_path "$source_spec"); then
      /bin/rm -rf "$installed_path"
    fi
    ;;
  *)
    exit 98
    ;;
esac
EOF
chmod +x "$pi"

cat > "$repair_sdk" <<'EOF'
import { appendFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

function packagePath(agentDir, sourceSpec) {
	if (sourceSpec.startsWith("npm:@llblab/pi-telegram@")) {
		return join(agentDir, "npm/node_modules/@llblab/pi-telegram");
	}
	if (sourceSpec.startsWith("npm:pi-web-access@")) {
		return join(agentDir, "npm/node_modules/pi-web-access");
	}
	if (sourceSpec.startsWith("npm:@ryan_nookpi/pi-extension-codex-fast-mode@")) {
		return join(agentDir, "npm/node_modules/@ryan_nookpi/pi-extension-codex-fast-mode");
	}
	if (sourceSpec.startsWith("git:github.com/algal/pi-openai-server-compaction@")) {
		return join(agentDir, "git/github.com/algal/pi-openai-server-compaction");
	}
	throw new Error(`unsupported fixture source: ${sourceSpec}`);
}

export class SettingsManager {
	static inMemory(settings) {
		return { settings };
	}
}

export class DefaultPackageManager {
	constructor({ agentDir, settingsManager }) {
		this.agentDir = agentDir;
		this.settingsManager = settingsManager;
	}

	async remove(sourceSpec) {
		appendFileSync(
			process.env.REPAIR_CALLS,
			`remove ${sourceSpec} via ${JSON.stringify(this.settingsManager.settings.npmCommand)}\n`,
		);
		rmSync(packagePath(this.agentDir, sourceSpec), { recursive: true, force: true });
	}

	async install(sourceSpec) {
		appendFileSync(
			process.env.REPAIR_CALLS,
			`install ${sourceSpec} via ${JSON.stringify(this.settingsManager.settings.npmCommand)}\n`,
		);
		const result = spawnSync(process.env.PI_FIXTURE_EXECUTABLE, ["install", sourceSpec], {
			env: { ...process.env, PI_CODING_AGENT_DIR: this.agentDir },
			stdio: "inherit",
		});
		if (result.status !== 0) throw new Error(`fixture install failed: ${result.status}`);
	}
}
EOF

fail() {
  printf 'pi-packages-convergence.test.sh: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  expected=$1
  actual=$2
  [ "$expected" = "$actual" ] || fail "expected '$expected', got '$actual'"
}

assert_source_present() {
  source_spec=$1
  jq -e --arg source "$source_spec" '
    any(.packages[]?; (if type == "string" then . else .source end) == $source)
  ' "$agent_dir/settings.json" >/dev/null || fail "missing configured source: $source_spec"
}

run_converger() {
  PATH="$runtime_bin" CALLS="$calls" REPAIR_CALLS="$repair_calls" STATE="$state" \
    PI_FIXTURE_EXECUTABLE="$pi" \
    PI_PACKAGE_MANAGER_SDK="$pi_package_manager_sdk" \
    PI_VERSION="${PI_VERSION:-0.84.3}" \
    /bin/bash "$CONVERGER" "$pi" "$agent_dir" "$EFFECTIVE_STATE_CHECKER" \
      "$INTEGRITY_CHECKER" "$integrity_contract" "$PACKAGE_REPAIRER" "$repair_sdk"
}

[ -x /usr/bin/awk ] || fail 'macOS system awk is unavailable for the activation contract'
[ ! -e "$runtime_bin/awk" ] || fail 'restricted activation fixture unexpectedly exposes awk'

# Preserve captain-owned runtime files and an unrelated package while a fresh
# agent directory receives all four reviewed packages.
printf '%s\n' '{"packages":["npm:unrelated@9.9.9"],"npmCommand":["captain-npm","--pinned"]}' > \
  "$agent_dir/settings.json"
mkdir -p "$agent_dir/state"
printf '%s\n' 'existing extension' > "$agent_dir/existing-extension.ts"
printf '%s\n' 'captain telegram config' > "$agent_dir/telegram.json"
printf '%s\n' 'captain web config' > "$TMP/web-search.json"
printf '%s\n' 'captain auth state' > "$agent_dir/auth.json"
printf '%s\n' 'captain fast-mode state' > "$agent_dir/state/codex-fast-mode.json"
printf '%s\n' 'captain compaction config' > "$agent_dir/openai-server-compaction.json"
: > "$calls"
: > "$repair_calls"
run_converger
expected_calls=$(cat <<'EOF'
install npm:@llblab/pi-telegram@0.39.2
install npm:pi-web-access@0.25.0
install npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6
install git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055
EOF
)
assert_eq "$expected_calls" "$(cat "$calls")"
assert_eq '' "$(cat "$repair_calls")"
assert_source_present 'npm:unrelated@9.9.9'
assert_source_present 'npm:@llblab/pi-telegram@0.39.2'
assert_source_present 'npm:pi-web-access@0.25.0'
assert_source_present 'npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6'
assert_source_present 'git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055'
for package_path in \
  "$agent_dir/npm/node_modules/@llblab/pi-telegram" \
  "$agent_dir/npm/node_modules/pi-web-access" \
  "$agent_dir/npm/node_modules/@ryan_nookpi/pi-extension-codex-fast-mode" \
  "$agent_dir/git/github.com/algal/pi-openai-server-compaction"; do
  [ -d "$package_path" ] || fail "package path was not created: $package_path"
done
jq -e '.name == "@llblab/pi-telegram" and .version == "0.39.2"' \
  "$agent_dir/npm/node_modules/@llblab/pi-telegram/package.json" >/dev/null
jq -e '.name == "pi-web-access" and .version == "0.25.0"' \
  "$agent_dir/npm/node_modules/pi-web-access/package.json" >/dev/null
jq -e '.name == "@ryan_nookpi/pi-extension-codex-fast-mode" and .version == "0.2.6"' \
  "$agent_dir/npm/node_modules/@ryan_nookpi/pi-extension-codex-fast-mode/package.json" >/dev/null
jq -e '.name == "pi-openai-server-compaction" and .version == "0.1.0"' \
  "$agent_dir/git/github.com/algal/pi-openai-server-compaction/package.json" >/dev/null
[ -f "$agent_dir/git/github.com/algal/pi-openai-server-compaction/src/index.ts" ] \
  || fail 'compaction extension entry point was not installed'
assert_eq 'c6d593087709e9481223dc6c6c2269b371b5e055' \
  "$(cat "$agent_dir/git/github.com/algal/pi-openai-server-compaction/.head")"
[ -e "$agent_dir/telegram.json" ] || fail 'Telegram config disappeared during fresh convergence'
[ -e "$TMP/web-search.json" ] || fail 'web-search config disappeared during fresh convergence'
[ -e "$agent_dir/auth.json" ] || fail 'Pi auth state disappeared during fresh convergence'
[ -e "$agent_dir/state/codex-fast-mode.json" ] || fail 'Codex fast-mode state disappeared during fresh convergence'
[ -e "$agent_dir/openai-server-compaction.json" ] || fail 'compaction config disappeared during fresh convergence'
[ -e "$agent_dir/existing-extension.ts" ] || fail 'existing Pi extension was removed during fresh convergence'

# A repeat activation is a no-op.
run_converger
assert_eq "$expected_calls" "$(cat "$calls")"
assert_eq '' "$(cat "$repair_calls")"

web_package_path="$agent_dir/npm/node_modules/pi-web-access"
printf '%s\n' 'modified web extension' > "$web_package_path/index.ts"
: > "$calls"
: > "$repair_calls"
run_converger
assert_eq 'install npm:pi-web-access@0.25.0' "$(cat "$calls")"
assert_eq 'export default function extension() {}' "$(cat "$web_package_path/index.ts")"
assert_eq 'remove npm:pi-web-access@0.25.0 via ["captain-npm","--pinned"]
install npm:pi-web-access@0.25.0 via ["captain-npm","--pinned"]' "$(cat "$repair_calls")"
jq -e '.npmCommand == ["captain-npm", "--pinned"]' "$agent_dir/settings.json" >/dev/null \
  || fail 'captain npmCommand changed during package repair'

# Complete object-form filters preserve every reviewed capability entry point.
for filtered_source in \
  'npm:@llblab/pi-telegram@0.39.2' \
  'npm:pi-web-access@0.25.0' \
  'npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6' \
  'git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055'; do
  jq --arg source "$filtered_source" '
    .packages = [.packages[] | if . == $source then {source: ., extensions: ["index.ts"]} else . end]
  ' "$agent_dir/settings.json" > "$state/settings.tmp"
  /bin/mv "$state/settings.tmp" "$agent_dir/settings.json"
  : > "$calls"
  run_converger
  assert_eq '' "$(cat "$calls")"
  jq -e --arg source "$filtered_source" '
    any(.packages[]?; type == "object" and .source == $source and .extensions == ["index.ts"])
  ' "$agent_dir/settings.json" >/dev/null || fail "complete filter was not preserved: $filtered_source"
done

printf '%s\n' 'modified filtered web extension' > "$web_package_path/index.ts"
: > "$calls"
: > "$repair_calls"
run_converger
assert_eq 'install npm:pi-web-access@0.25.0' "$(cat "$calls")"
assert_eq 'export default function extension() {}' "$(cat "$web_package_path/index.ts")"
jq -e '
  any(.packages[]?;
    type == "object"
    and .source == "npm:pi-web-access@0.25.0"
    and .extensions == ["index.ts"])
' "$agent_dir/settings.json" >/dev/null || fail 'complete filter was lost during integrity repair'
assert_eq 'remove npm:pi-web-access@0.25.0 via ["captain-npm","--pinned"]
install npm:pi-web-access@0.25.0 via ["captain-npm","--pinned"]' "$(cat "$repair_calls")"

jq '
  .packages = [.packages[] |
    if type == "object" and .source == "npm:@llblab/pi-telegram@0.39.2"
    then . + {skills: []}
    else .
    end]
' "$agent_dir/settings.json" > "$state/settings.tmp"
/bin/mv "$state/settings.tmp" "$agent_dir/settings.json"
: > "$calls"
run_converger
assert_eq 'remove npm:@llblab/pi-telegram@0.39.2
install npm:@llblab/pi-telegram@0.39.2' "$(cat "$calls")"
assert_source_present 'npm:@llblab/pi-telegram@0.39.2'

compaction_path="$agent_dir/git/github.com/algal/pi-openai-server-compaction"
printf '%s\n' 'modified extension' > "$compaction_path/src/index.ts"
: > "$compaction_path/.dirty"
: > "$calls"
: > "$repair_calls"
run_converger
assert_eq 'install git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055' "$(cat "$calls")"
assert_eq 'export default function extension() {}' "$(cat "$compaction_path/src/index.ts")"
[ ! -e "$compaction_path/.dirty" ] || fail 'dirty compaction checkout was not repaired'
jq -e '
  any(.packages[]?;
    type == "object"
    and .source == "git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055"
    and .extensions == ["index.ts"])
' "$agent_dir/settings.json" >/dev/null || fail 'compaction filter was lost during source repair'
assert_eq 'remove git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055 via ["captain-npm","--pinned"]
install git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055 via ["captain-npm","--pinned"]' "$(cat "$repair_calls")"

# Pi uses the first same-identity entry. A disabling filter followed by an
# exact unfiltered duplicate is normalized to one active reviewed pin.
jq '.packages = [{"source":"npm:pi-web-access@0.25.0","extensions":[]}, "npm:pi-web-access@0.25.0"] + .packages' \
  "$agent_dir/settings.json" > "$state/settings.tmp"
/bin/mv "$state/settings.tmp" "$agent_dir/settings.json"
: > "$calls"
run_converger
assert_eq 'remove npm:pi-web-access@0.25.0
install npm:pi-web-access@0.25.0' "$(cat "$calls")"
assert_eq '1' "$(jq '[.packages[] | select(. == "npm:pi-web-access@0.25.0")] | length' "$agent_dir/settings.json")"

# Floating filtered identities are repaired to the exact pin in one activation.
jq '.packages = [{"source":"npm:pi-web-access","extensions":[]}] + [.packages[] | select(. != "npm:pi-web-access@0.25.0")]' \
  "$agent_dir/settings.json" > "$state/settings.tmp"
/bin/mv "$state/settings.tmp" "$agent_dir/settings.json"
: > "$calls"
run_converger
assert_eq 'remove npm:pi-web-access@0.25.0
install npm:pi-web-access@0.25.0' "$(cat "$calls")"
assert_source_present 'npm:pi-web-access@0.25.0'

# Stale configured versions and refs are repaired to the reviewed pins, and the
# unrelated package remains configured.
cat > "$agent_dir/settings.json" <<'EOF'
{"packages":[
  "npm:@llblab/pi-telegram@0.39.1",
  {"source":"npm:pi-web-access@0.24.2","extensions":[]},
  "npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.5",
  "git:github.com/algal/pi-openai-server-compaction@old-ref",
  "npm:unrelated@9.9.9"
],"npmCommand":["captain-npm","--pinned"]}
EOF
: > "$calls"
printf '%s\n' '{"name":"@llblab/pi-telegram","version":"0.39.1","pi":{"extensions":["./index.ts"]}}' > \
  "$agent_dir/npm/node_modules/@llblab/pi-telegram/package.json"
printf '%s\n' '{"name":"pi-web-access","version":"0.24.2","pi":{"extensions":["./index.ts"]}}' > \
  "$agent_dir/npm/node_modules/pi-web-access/package.json"
printf '%s\n' '{"name":"@ryan_nookpi/pi-extension-codex-fast-mode","version":"0.2.5","pi":{"extensions":["./index.ts"]}}' > \
  "$agent_dir/npm/node_modules/@ryan_nookpi/pi-extension-codex-fast-mode/package.json"
printf '%s\n' 'old-ref' > "$agent_dir/git/github.com/algal/pi-openai-server-compaction/.head"
run_converger
expected_stale_calls=$(cat <<'EOF'
remove npm:@llblab/pi-telegram@0.39.2
install npm:@llblab/pi-telegram@0.39.2
remove npm:pi-web-access@0.25.0
install npm:pi-web-access@0.25.0
remove npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6
install npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6
remove git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055
install git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055
EOF
)
assert_eq "$expected_stale_calls" "$(cat "$calls")"
assert_source_present 'npm:unrelated@9.9.9'
assert_source_present 'npm:@llblab/pi-telegram@0.39.2'
assert_source_present 'npm:pi-web-access@0.25.0'
assert_source_present 'npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6'
assert_source_present 'git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055'
jq -e 'all(.packages[]; type == "string")' "$agent_dir/settings.json" >/dev/null \
  || fail 'stale package filter remained active'
[ -e "$agent_dir/existing-extension.ts" ] || fail 'existing Pi extension was removed during stale repair'
[ -e "$agent_dir/telegram.json" ] || fail 'Telegram config was changed during stale repair'
[ -e "$TMP/web-search.json" ] || fail 'web-search config was changed during stale repair'
[ -e "$agent_dir/auth.json" ] || fail 'Pi auth state was changed during stale repair'

# Refuse the reviewed compaction source outside the Pi version for which the
# isolated compatibility audit was completed, before reading or changing any
# package state.
bad_state="$TMP/bad-pi-state"
bad_calls="$TMP/bad-calls"
bad_agent="$TMP/bad-agent"
mkdir -p "$bad_state" "$bad_agent"
if PATH="$runtime_bin" CALLS="$bad_calls" STATE="$bad_state" PI_VERSION='0.84.4' \
  REPAIR_CALLS="$repair_calls" PI_FIXTURE_EXECUTABLE="$pi" \
  PI_PACKAGE_MANAGER_SDK="$pi_package_manager_sdk" \
  /bin/bash "$CONVERGER" "$pi" "$bad_agent" "$EFFECTIVE_STATE_CHECKER" \
    "$INTEGRITY_CHECKER" "$integrity_contract" "$PACKAGE_REPAIRER" "$repair_sdk" \
    >"$TMP/incompatible.out" 2>"$TMP/incompatible.err"; then
  fail 'incompatible Pi version was accepted'
fi
[ ! -e "$bad_calls" ] || [ ! -s "$bad_calls" ] || fail 'incompatible Pi version triggered an install'
grep -Fq 'refusing reviewed package pins' "$TMP/incompatible.err" \
  || fail 'incompatible-version refusal was not reported'
[ ! -e "$bad_agent/npm" ] || fail 'incompatible Pi version created package storage'

printf 'ok - fresh install, idempotent repeat, authenticated package repair, complete-filter preservation, npmCommand preservation, filtered-entry repair, stale pin repair, unrelated-package preservation, restricted PATH, and incompatible-version refusal\n'
