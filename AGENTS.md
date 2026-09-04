# Agent Instructions

## General Preferences
- Prioritize scalable architecture over development speed.
- Never use m-dashes.
- Do not automatically add yourself as a co-author on git commits.

## Git Workflow
- Never commit directly to `main`.
- Create a short-lived feature branch for every change.
- Push the branch and open a pull request so the result can be reviewed on GitHub.
- Do not merge pull requests unless Kevin explicitly authorizes the merge.
- Keep unrelated local changes out of the pull request.

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

### 4. no-mistakes pipeline agent
Do not Home Manager-link `~/.no-mistakes/config.yaml`; rebuilds patch Pi + Grok routing through `agents/materialize-no-mistakes-config.py`.
Firstmate owns the Astra review slot. See `docs/firstmate-toolchain.md`.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
