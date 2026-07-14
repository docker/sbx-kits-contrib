# Colorized prompt for xterm-kitty and other color-capable terminals.
case "$TERM" in
  xterm-color|*-256color|xterm-kitty) _kitty_color_prompt=yes ;;
esac
if [ "${_kitty_color_prompt:-}" = yes ]; then
  PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\W\[\033[00m\]\$ '
fi
unset _kitty_color_prompt

# Load Kitty shell integration when connected via kitten ssh.
# The kitten sets KITTY_INSTALLATION_DIR to the remote pre-installed directory.
if [ -n "${KITTY_INSTALLATION_DIR:-}" ]; then
  export KITTY_SHELL_INTEGRATION="enabled"
  . "$KITTY_INSTALLATION_DIR/shell-integration/bash/kitty.bash"
fi
