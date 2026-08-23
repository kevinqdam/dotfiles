{ config, lib, pkgs, ... }:
let
  firstmateToolchain = import ./nix/firstmate-toolchain.nix { inherit pkgs; };
in {
  home.username = "kevindam";
  home.homeDirectory = "/Users/kevindam";

  home.sessionVariables = {
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

  # Link AGENTS.md to AntiGravity CLI dir
  home.file.".gemini/antigravity-cli/agents.md".source = ./AGENTS.md;

  # These are captain-owned operational settings, not Home Manager links. The
  # activation helper creates only missing regular files and preserves any
  # locally changed regular file in the populated canonical home.
  home.activation.firstmateConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.bash}/bin/bash ${./agents/materialize-firstmate-config} \
      "${config.home.homeDirectory}/.local/share/firstmate"
  '';

  # Global Pi integration. It is inert until /firstmate is invoked.
  home.file.".pi/agent/extensions/firstmate-bootstrap.ts".source = ./agents/pi/extensions/firstmate-bootstrap.ts;
  home.file.".local/bin/setup-harnesses".source = ./agents/setup-harnesses;

  home.stateVersion = "24.05";
}
