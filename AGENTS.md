# Agent Instructions

## General Preferences
- Prioritize scalable architecture over development speed.
- Never use m-dashes.
- Do not automatically add yourself as a co-author on git commits.

## Declarative System Rules (Nix & Home Manager)
This system is fully declarative and managed by **Nix, Nix-Darwin, Nix-Homebrew, and Home Manager**. 

### 1. Installing / Removing Packages
- **Never** run global imperative package managers (e.g., `brew install`, `npm install -g`, `pip install`, `gem install`) to install system-wide tools.
- To install/remove command-line tools: Add/remove them in `~/dev/dotfiles/home.nix` under `home.packages`.
- To install/remove macOS GUI apps: Add/remove them in `~/dev/dotfiles/darwin-configuration.nix` under `homebrew.casks`.
- To install/remove macOS-specific Homebrew formulae: Add/remove them in `~/dev/dotfiles/darwin-configuration.nix` under `homebrew.brews`.

### 2. Modifying Configurations (Dotfiles)
- Do **not** attempt to modify configuration files (like `~/.zshrc`, `~/.gitconfig`, `~/.vimrc`, `~/.config/...`) directly in the home directory. They are read-only symlinks managed by Home Manager.
- To modify configurations, edit the corresponding source files inside `~/dev/dotfiles/` (e.g., `home.nix` or `darwin-configuration.nix`).

### 3. Applying Changes
- After making any changes to the Nix configuration, run the rebuild script:
  ```bash
  cd ~/.dotfiles
  ./rebuild.sh
  ```
- **Do not** run `sudo ./rebuild.sh`. The script runs `nix build` as the user and escalates to `sudo` internally only when activating the system.
