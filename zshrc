# Powerlevel10k instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# v2g function
function v2g() {
  src="" # required
  target="" # optional (defaults to source file name)
  resolution="" # optional (defaults to source video resolution)
  fps="" # optional (defaults to 10 fps -- helps drop frames)

  while [ $# -gt 0 ]; do
    if [[ $1 == *"--"* ]]; then
      param="${1/--/}"
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

  basename=${target%.*}
  [[ ${#basename} = 0 ]] && basename=$target
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
export PATH="/usr/local/smlnj/bin:/Applications/Racket v7.4/bin:/usr/local/bin:/usr/local/sbin:$PATH"

# Nix Rebuild Shortcut
alias nix-rebuild="~/.dotfiles/rebuild.sh"
