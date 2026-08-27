{ config, lib, pkgs, ... }: {
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
      upgrade = false;
      cleanup = "none";
      extraEnv.HOMEBREW_FORCE_API_AUTO_UPDATE = "1";
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
      {
        name = "antigravity-cli";
        greedy = true;
      }
      "chatgpt"
      "codex"
      "google-drive"
      "google-chrome"
      "google-gemini"
      "iterm2"
      "logitune"
      "raycast"
      "superwhisper"
      "tailscale-app"
      "visual-studio-code"
    ];
  };

  # nix-homebrew's declarative Taps link cannot replace an ordinary legacy
  # directory. Prepare only the native prefix immediately before its setup.
  system.activationScripts.setup-homebrew.text = lib.mkBefore ''
    ${./agents/migrate-empty-homebrew-taps} \
      ${lib.escapeShellArg config.nix-homebrew.prefixes.${config.nix-homebrew.defaultArm64Prefix}.library} \
      ${lib.escapeShellArg config.nix-homebrew.user} \
      root \
      ${lib.escapeShellArg config.nix-homebrew.group}
  '';

}
