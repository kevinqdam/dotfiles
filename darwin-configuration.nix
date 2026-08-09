{ pkgs, ... }: {
  nix.enable = false;

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  programs.zsh.enable = true;

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
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap";
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
      "codex"
      "google-drive"
      "google-gemini"
      "iterm2"
      "logitune"
      "raycast"
      "superwhisper"
      "visual-studio-code"
    ];
  };
}
