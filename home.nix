{ config, pkgs, ... }: {
  home.username = "kevindam";
  home.homeDirectory = "/Users/kevindam";

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
    gobject-introspection
    htop
    libtool
    nghttp2
    nodejs
    openjdk
    perl
    python3
    tldr
    tmux
    tree
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

  home.stateVersion = "24.05";
}
