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
    npmDepsHash = "sha256-S/XwdHQYIlYzG5s+WC06I2X+H2BCpTAqbvkhV5yzTJY=";
    npmBuildScript = "build";
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postInstall = ''
      nodeModules="$out/lib/node_modules/firstmate-axi-toolchain/node_modules"
      install -d "$out/bin"

      makeWrapper "${pkgs.nodejs_22}/bin/node" "$out/bin/gh-axi" \
        --add-flags "$nodeModules/gh-axi/dist/bin/gh-axi.js" \
        --set NODE_PATH "$nodeModules"
      makeWrapper "${pkgs.nodejs_22}/bin/node" "$out/bin/chrome-devtools-axi" \
        --add-flags "$nodeModules/chrome-devtools-axi/dist/bin/chrome-devtools-axi.js" \
        --set NODE_PATH "$nodeModules" \
        --set CHROME_DEVTOOLS_AXI_MCP_PATH "$nodeModules/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js"
      makeWrapper "${pkgs.nodejs_22}/bin/node" "$out/bin/lavish-axi" \
        --add-flags "$nodeModules/lavish-axi/dist/cli.mjs" \
        --set NODE_PATH "$nodeModules"
      makeWrapper "${pkgs.nodejs_22}/bin/node" "$out/bin/tasks-axi" \
        --add-flags "$nodeModules/tasks-axi/dist/bin/tasks-axi.js" \
        --set NODE_PATH "$nodeModules"
      makeWrapper "${pkgs.nodejs_22}/bin/node" "$out/bin/quota-axi" \
        --add-flags "$nodeModules/quota-axi/dist/bin/quota-axi.js" \
        --set NODE_PATH "$nodeModules"
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
