{ lib, pkgs, ... }: {
  nix.enable = false;

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  programs.zsh = {
    enable = true;
    interactiveShellInit = lib.mkAfter ''
      # Homebrew's shellenv has already added the native prefix. Remove the
      # legacy Intel completion directory before nix-darwin runs compinit.
      fpath=(''${fpath:#/usr/local/share/zsh/site-functions})
    '';
  };

  system.configurationRevision = null;
  system.stateVersion = 5;
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Security / Pam
  security.pam.services.sudo_local.touchIdAuth = true;

  # Define the user so Home Manager knows the home directory
  users.users.kevindam = {
    name = "kevindam";
    home = "/Users/kevindam";
  };

  system.primaryUser = "kevindam";

  homebrew = {
    enable = true;
    onActivation = {
      # The locked nix-homebrew brew source is the update boundary. Do not
      # replace it with a mutable Homebrew update during activation.
      autoUpdate = false;
      upgrade = true;
      cleanup = "none";
    };
    
    taps = [
    ];

    brews = [
      "blueutil"
      "herdr"
      "mono"
      "mysql" 
      "mysql-client"
      "pi-coding-agent"
      "tcl-tk" 
    ];

    casks = [
      "anaconda"
      "antigravity-cli"
      "chatgpt"
      "codex"
      "google-drive"
      "google-gemini"
      "iterm2"
      "logitune"
      "raycast"
      "superwhisper"
      "tailscale-app"
      "visual-studio-code"
    ];
  };
}
