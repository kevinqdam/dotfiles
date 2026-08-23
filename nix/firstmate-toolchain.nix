{ pkgs }:
let
  noMistakesVersion = "1.57.0";
  treehouseVersion = "2.0.1";

  noMistakes = pkgs.stdenvNoCC.mkDerivation {
    pname = "no-mistakes";
    version = noMistakesVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/kunchenguid/no-mistakes/releases/download/v${noMistakesVersion}/no-mistakes-v${noMistakesVersion}-darwin-arm64.tar.gz";
      sha256 = "b621637578afcd62bc0e8ddbe829d08ee093079d0e5fbb9edd1f15f7cfffe635";
    };
    dontUnpack = true;
    installPhase = ''
      install -d "$out/bin"
      tar -xzf "$src" -C "$out/bin"
      chmod 0755 "$out/bin/no-mistakes"
    '';
    meta = {
      description = "Automated review, test, lint, push, PR, and CI gate";
      homepage = "https://github.com/kunchenguid/no-mistakes";
      license = pkgs.lib.licenses.mit;
      platforms = [ "aarch64-darwin" ];
      mainProgram = "no-mistakes";
    };
  };

  treehouse = pkgs.stdenvNoCC.mkDerivation {
    pname = "treehouse";
    version = treehouseVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/kunchenguid/treehouse/releases/download/v${treehouseVersion}/treehouse-v${treehouseVersion}-darwin-arm64.tar.gz";
      sha256 = "7ee5078f3d1f33c01196548797fce65408e459d53530b77d4ba56e074fa1c1a2";
    };
    dontUnpack = true;
    installPhase = ''
      install -d "$out/bin"
      tar -xzf "$src" -C "$out/bin"
      chmod 0755 "$out/bin/treehouse"
    '';
    meta = {
      description = "Pinned git worktree provider used by Firstmate";
      homepage = "https://github.com/kunchenguid/treehouse";
      license = pkgs.lib.licenses.mit;
      platforms = [ "aarch64-darwin" ];
      mainProgram = "treehouse";
    };
  };

  axiTools = pkgs.buildNpmPackage {
    pname = "firstmate-axi-toolchain";
    version = "2026-08-23";
    src = ./axi-tools;
    nodejs = pkgs.nodejs_22;
    npmDepsHash = "sha256-UjYi2ucucX5ouOAseAc+cD4sx1ZP0mnpZfiIbJKwb1U=";
    npmBuildScript = "build";
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postInstall = ''
      install -d "$out/lib/node_modules"
      cp -R node_modules/. "$out/lib/node_modules/"
      install -d "$out/bin"

      makeWrapper "${pkgs.nodejs_22}/bin/node" "$out/bin/gh-axi" \
        --add-flags "$out/lib/node_modules/gh-axi/dist/bin/gh-axi.js" \
        --set NODE_PATH "$out/lib/node_modules"
      makeWrapper "${pkgs.nodejs_22}/bin/node" "$out/bin/chrome-devtools-axi" \
        --add-flags "$out/lib/node_modules/chrome-devtools-axi/dist/bin/chrome-devtools-axi.js" \
        --set NODE_PATH "$out/lib/node_modules"
      makeWrapper "${pkgs.nodejs_22}/bin/node" "$out/bin/lavish-axi" \
        --add-flags "$out/lib/node_modules/lavish-axi/dist/cli.mjs" \
        --set NODE_PATH "$out/lib/node_modules"
      makeWrapper "${pkgs.nodejs_22}/bin/node" "$out/bin/tasks-axi" \
        --add-flags "$out/lib/node_modules/tasks-axi/dist/bin/tasks-axi.js" \
        --set NODE_PATH "$out/lib/node_modules"
      makeWrapper "${pkgs.nodejs_22}/bin/node" "$out/bin/quota-axi" \
        --add-flags "$out/lib/node_modules/quota-axi/dist/bin/quota-axi.js" \
        --set NODE_PATH "$out/lib/node_modules"
    '';
    meta = {
      description = "Pinned Firstmate AXI command-line toolchain";
      homepage = "https://github.com/kunchenguid/gh-axi";
      license = pkgs.lib.licenses.mit;
      platforms = pkgs.lib.platforms.darwin;
    };
  };

in {
  inherit axiTools noMistakes treehouse;
}
