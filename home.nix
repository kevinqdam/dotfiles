{ config, lib, pkgs, ... }:
let
  firstmateToolchain = import ./nix/firstmate-toolchain.nix { inherit pkgs; };
  piWithVim = import ./nix/pi-with-vim.nix { inherit pkgs; };
  vscodeUserDirectory = "Library/Application Support/Code/User";
  firstmateConfigMaterializer = pkgs.stdenv.mkDerivation {
    pname = "firstmate-config-materializer";
    version = "1.0.0";
    src = ./agents/materialize-firstmate-config.c;
    dontUnpack = true;
    buildPhase = ''
      $CC -std=c11 -Wall -Wextra -Werror "$src" -o materialize-firstmate-config
    '';
    installPhase = ''
      install -d "$out/bin"
      install -m755 materialize-firstmate-config "$out/bin/materialize-firstmate-config"
    '';
  };
in {
  home.username = "kevindam";
  home.homeDirectory = "/Users/kevindam";

  home.sessionVariables = {
    AGY_CLI_DISABLE_AUTO_UPDATE = "true";
    FIRSTMATE_ROOT = "${config.home.homeDirectory}/dev/firstmate";
    FIRSTMATE_HOME = "${config.home.homeDirectory}/.local/share/firstmate";
    # FM_HOME is the one primary operational home. Secondmate launches pass
    # their own FM_HOME explicitly and therefore retain their isolated homes.
    FM_HOME = "${config.home.homeDirectory}/.local/share/firstmate";
  };

  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [
    automake
    broot
    cmake
    coreutils
    deno
    ffmpeg
    fzf
    gifsicle
    gh
    git
    gnupg
    jq
    gobject-introspection
    htop
    libtool
    nghttp2
    nodejs_22
    openjdk
    perl
    python3
    tldr
    tmux
    tree
    actionlint
    shellcheck
    firstmateToolchain.axiTools
    firstmateToolchain.noMistakes
    firstmateToolchain.treehouse
    piWithVim
  ];

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Kevin Dam";
        email = "kevinqdam@gmail.com";
      };
      credential.helper = "osxkeychain";
      init.defaultBranch = "main";
      color.ui = "auto";
      pull.rebase = false;
      pager.branch = false;
    };
  };

  programs.vim = {
    enable = true;
    plugins = with pkgs.vimPlugins; [
      material-vim
      onedark-vim
    ];
    extraConfig = builtins.readFile ./vimrc;
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
    };

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];

    initContent = builtins.readFile ./zshrc;
  };

  # VS Code is installed by the Homebrew cask; keep its user preferences in
  # the same Home Manager-linked profile as the other declarative settings.
  home.file."${vscodeUserDirectory}/settings.json".source = ./vscode/settings.json;
  home.file."${vscodeUserDirectory}/keybindings.json".source = ./vscode/keybindings.json;

  # The VS Code cask does not install extensions. Ensure every audited
  # extension ID is present without updating or removing other extensions.
  home.activation.vscodeExtensions = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    code="/opt/homebrew/bin/code"
    if [ ! -x "$code" ]; then
      echo "Home Manager: VS Code CLI is unavailable; audited extensions were not installed" >&2
      exit 1
    fi

    installed="$($code --list-extensions)"
    while IFS= read -r extension; do
      [ -n "$extension" ] || continue
      if ! printf '%s\n' "$installed" | grep -Fqx "$extension"; then
        "$code" --install-extension "$extension"
      fi
    done < ${./vscode/extensions.txt}
  '';

  # Link AGENTS.md to AntiGravity CLI dir
  home.file.".gemini/antigravity-cli/agents.md".source = ./AGENTS.md;

  # These are captain-owned operational settings, not Home Manager links. The
  # activation helper creates only missing regular files and preserves any
  # locally changed regular file in the populated canonical home.
  home.activation.firstmateConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${firstmateConfigMaterializer}/bin/materialize-firstmate-config \
      "${config.home.homeDirectory}/.local/share/firstmate"
  '';

  # Do not Home Manager-link ~/.no-mistakes/config.yaml: that would smash live
  # daemon state. Patch only the pipeline-agent routing keys on rebuild.
  home.activation.noMistakesConfig = lib.hm.dag.entryAfter [ "firstmateConfig" ] ''
    ${pkgs.python3}/bin/python3 ${./agents/materialize-no-mistakes-config.py} \
      "${config.home.homeDirectory}/.no-mistakes"
  '';

  # Homebrew installs Pi before Home Manager activation. Let Pi own its
  # ordinary-writable package settings and storage; do not link connector,
  # provider, or runtime configuration into the declarative profile.
  home.activation.piPackages = lib.hm.dag.entryAfter [ "firstmateConfig" ] ''
    # Home Manager activation runs with a restricted PATH. Include the
    # declarative Git runtime explicitly because Pi's Git package source needs
    # it even when the user's profile or ambient shell PATH is unavailable.
    PATH="/opt/homebrew/bin:${pkgs.nodejs_22}/bin:${pkgs.jq}/bin:${pkgs.git}/bin:$PATH"
    export PATH
    ${./agents/converge-pi-packages} \
      "/opt/homebrew/bin/pi" \
      "${config.home.homeDirectory}/.pi/agent" \
      "${./agents/pi-effective-package-state.mjs}" \
      "${./agents/pi-package-integrity.mjs}" \
      "${./agents/pi-package-integrity.json}" \
      "${./agents/pi-repair-package.mjs}" \
      "${./agents/pi-normalize-package.mjs}"
  '';

  # Global Pi integration. It is inert until /firstmate is invoked.
  home.file.".pi/agent/extensions/firstmate-bootstrap.ts".source = ./agents/pi/extensions/firstmate-bootstrap.ts;
  home.file.".local/bin/setup-harnesses".source = ./agents/setup-harnesses;

  home.stateVersion = "24.05";
}
