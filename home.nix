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
    rbenv
    tldr
    tmux
    tree
    zsh-powerlevel10k
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
    extraConfig = ''
      " Vim is based on Vi. Setting `nocompatible` switches from the default
      " Vi-compatibility mode and enables useful Vim functionality.
      set nocompatible

      " Turn on syntax highlighting.
      syntax on

      " Disable the default Vim startup message.
      set shortmess+=I

      " Show line numbers.
      set number

      " Set system clipboard as the default register
      set clipboard=unnamed

      " Always show the status line at the bottom, even if you only have one window open.
      set laststatus=2

      " Backspace behave more reasonably.
      set backspace=indent,eol,start

      " Enable hidden buffers.
      set hidden

      " Search case-insensitive when all characters in search are lowercase.
      set ignorecase
      set smartcase

      " Enable searching as you type.
      set incsearch

      " Unbind Ex mode.
      nmap Q <Nop>

      " Disable audible bell.
      set noerrorbells visualbell t_vb=

      " Enable mouse support.
      set mouse+=a

      " Allow using jj to exit INSERT mode.
      inoremap jj <ESC>

      " Termguicolors setup
      if (has('termguicolors'))
        set termguicolors
      endif

      " Fix italics in Vim
      if !has('nvim')
        let &t_ZH="\e[3m"
        let &t_ZR="\e[23m"
      endif

      let g:material_terminal_italics = 1
      let g:onedark_terminal_italics = 1
      let g:material_theme_style = 'onedark'
      colorscheme onedark
    '';
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

    initContent = ''
      # Powerlevel10k instant prompt
      if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
        source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
      fi

      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme

      # v2g function
      function v2g() {
        src="" # required
        target="" # optional (defaults to source file name)
        resolution="" # optional (defaults to source video resolution)
        fps="" # optional (defaults to 10 fps -- helps drop frames)

        while [ $# -gt 0 ]; do
          if [[ $1 == *"--"* ]]; then
            param="''${1/--/}"
            declare $param="$2"
          fi
          shift
        done

        if [[ -z $src ]]; then
          echo -e "\nPlease call 'v2g --src <source video file>' to run this command\n"
          return 1
        fi

        if [[ -z $target ]]; then
          target=$src
        fi

        basename=''${target%.*}
        [[ ''${#basename} = 0 ]] && basename=$target
        target="$basename.gif"

        if [[ -n $fps ]]; then
          fps="-r $fps"
        fi

        if [[ -n $resolution ]]; then
          resolution="-s $resolution"
        fi

        echo "ffmpeg -i \"$src\" -pix_fmt rgb8 $fps $resolution \"$target\" && gifsicle -O3 \"$target\" -o \"$target\""
        ffmpeg -i "$src" -pix_fmt rgb8 $fps $resolution "$target" && gifsicle -O3 "$target" -o "$target"
        osascript -e "display notification \"$target successfully converted and saved\" with title \"v2g complete\""
      }

      # Include p10k config
      [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

      # Setup paths (moved from bash_profile and zshrc)
      export CPLUS_INCLUDE_PATH="/usr/local/include"
      export LIBRARY_PATH="/usr/local/lib"
      export PATH="$HOME/.rbenv/bin:/usr/local/smlnj/bin:/Applications/Racket v7.4/bin:/usr/local/bin:/usr/local/sbin:$PATH"
      
      eval "$(rbenv init - zsh)"
    '';
  };

  # Link AGENTS.md to AntiGravity CLI dir
  home.file.".gemini/antigravity-cli/agents.md".source = ./AGENTS.md;

  home.stateVersion = "24.05";
}
