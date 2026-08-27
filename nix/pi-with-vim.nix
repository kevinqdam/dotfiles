{ pkgs, piExecutable ? "/opt/homebrew/bin/pi" }:

pkgs.writeShellScriptBin "pi" ''
  export VISUAL=vim
  export EDITOR=vim
  exec ${pkgs.lib.escapeShellArg piExecutable} "$@"
''
