#!/bin/bash
#shellcheck disable=SC2317  # Unreachable code warnings for show_usage()
#
# install.sh - Installation script for shlock
#
# DESCRIPTION:
#   Builds and installs the shlock script and manpage.
#   Supports custom installation prefixes and provides interactive confirmation.
#
# USAGE:
#   ./install.sh [OPTIONS] [ACTION]
#
# ACTIONS:
#   build            - Build shlock.1 from shlock.1.md (default)
#   install          - Install script, manpage, and completion
#   install-script   - Install only the script
#   install-man      - Install only the manpage
#   install-completion - Install only bash completion
#   uninstall        - Remove script, manpage, and completion
#   uninstall-script - Remove only the script
#   uninstall-man    - Remove only the manpage
#   uninstall-completion - Remove only bash completion
#   clean            - Remove generated shlock.1
#
# OPTIONS:
#   --prefix DIR    Installation prefix (default: /usr/local)
#   -y, --yes       Skip confirmation prompts
#   -h, --help      Display this help message
#
# EXAMPLES:
#   ./install.sh build
#   ./install.sh install
#   ./install.sh --prefix /usr install
#   ./install.sh --prefix ~/.local install
#   ./install.sh -y install
#   ./install.sh install-script
#   ./install.sh install-man
#   ./install.sh install-completion
#   ./install.sh uninstall
#   ./install.sh clean
#
# EXIT CODES:
#   0 - Success
#   1 - Dependency missing or operation failed
#   2 - Invalid arguments
#
set -euo pipefail
shopt -s inherit_errexit

declare -rx PATH=/usr/local/bin:/usr/bin:/bin

declare -r SCRIPT_NAME=${0##*/}
declare -r VERSION='1.0.0'

# Default values
declare -- PREFIX='/usr/local'
declare -i SKIP_CONFIRM=0
declare -- ACTION='build'

# File paths
declare -r SCRIPT='shlock'
declare -r SOURCE='shlock.1.md'
declare -r TARGET='shlock.1'
declare -r COMPLETION_SRC='shlock.bash_completion'
declare -r COMPLETION_DEST='shlock'

# Error handling
error() { >&2 echo "$SCRIPT_NAME: $*"; }

die() { (($# < 2)) || error "${@:2}"; exit "${1:-0}"; }

# Show usage information
show_usage() {
  cat <<'EOF'
USAGE:
  install.sh [OPTIONS] [ACTION]

ACTIONS:
  build              Build shlock.1 from shlock.1.md (default)
  install            Install script, manpage, and completion
  install-script     Install only the script
  install-man        Install only the manpage
  install-completion Install only bash completion
  uninstall          Remove script, manpage, and completion
  uninstall-script   Remove only the script
  uninstall-man      Remove only the manpage
  uninstall-completion Remove only bash completion
  clean              Remove generated shlock.1

OPTIONS:
  --prefix DIR    Installation prefix (default: /usr/local)
  -y, --yes       Skip confirmation prompts
  -h, --help      Display this help message

EXAMPLES:
  ./install.sh build
  ./install.sh install
  ./install.sh --prefix /usr install
  ./install.sh --prefix ~/.local install
  ./install.sh -y install
  ./install.sh install-script
  ./install.sh install-man
  ./install.sh install-completion
  ./install.sh uninstall
  ./install.sh clean

PATH AND MANPATH CONFIGURATION:
  If installing to a custom prefix, you may need to update PATH and MANPATH:

  # Add to ~/.bashrc or ~/.profile:
  export PATH="$PREFIX/bin:$PATH"
  export MANPATH="$PREFIX/share/man:$MANPATH"

  Or create /etc/man_db.conf.d/local.conf:
  MANPATH_MAP /usr/local/bin /usr/local/share/man

EXIT CODES:
  0 - Success
  1 - Dependency missing or operation failed
  2 - Invalid arguments
EOF
}

# Check if pandoc is installed
check_pandoc() {
  if ! command -v pandoc >/dev/null 2>&1; then
    error 'pandoc is not installed'
    error ''
    error 'Install with:'
    error '  Debian/Ubuntu: sudo apt install pandoc'
    error '  Fedora/RHEL:   sudo dnf install pandoc'
    error '  macOS:         brew install pandoc'
    die 1
  fi
}

# Confirm action with user
confirm() {
  local -- prompt=$1
  #shellcheck disable=SC2015  # return 0 cannot fail; ||: is a set -e guard
  ((SKIP_CONFIRM)) && return 0 ||:
  local -- response
  read -r -p "$prompt [y/N] " response
  [[ "$response" =~ ^[Yy]$ ]]
}

# Build the manpage
build_manpage() {
  echo "Building manpage: $TARGET"
  [[ -f "$SOURCE" ]] || die 1 "Source file $SOURCE not found"
  check_pandoc
  pandoc --standalone --to man -o "$TARGET" "$SOURCE" || \
    die 1 'Failed to build manpage'
  echo "✓ Manpage built successfully: $TARGET"
}

# Install the script
install_script() {
  local -- bindir="$PREFIX/bin"
  [[ -f "$SCRIPT" ]] || die 1 "Script file $SCRIPT not found"
  echo "Installing script to $bindir/$SCRIPT"
  mkdir -p "$bindir" || die 1 "Failed to create directory $bindir"
  install -m 755 "$SCRIPT" "$bindir/$SCRIPT" || \
    die 1 'Failed to install script (try with sudo?)'
  echo '✓ Script installed'
}

# Install the manpage
install_manpage() {
  local -- mandir="$PREFIX/share/man/man1"
  build_manpage
  echo "Installing manpage to $mandir/$TARGET"
  mkdir -p "$mandir" || die 1 "Failed to create directory $mandir"
  install -m 644 "$TARGET" "$mandir/$TARGET" || \
    die 1 'Failed to install manpage (try with sudo?)'
  echo 'Updating man database...'
  mandb -q 2>/dev/null ||:
  echo '✓ Manpage installed'
}

# Install the bash completion
install_completion() {
  local -- completiondir="$PREFIX/share/bash-completion/completions"
  [[ -f "$COMPLETION_SRC" ]] || die 1 "Completion file $COMPLETION_SRC not found"
  echo "Installing bash completion to $completiondir/$COMPLETION_DEST"
  mkdir -p "$completiondir" || die 1 "Failed to create directory $completiondir"
  install -m 644 "$COMPLETION_SRC" "$completiondir/$COMPLETION_DEST" || \
    die 1 'Failed to install completion (try with sudo?)'
  echo '✓ Bash completion installed'
}

# Install script, manpage, and completion
install_all() {
  local -- bindir="$PREFIX/bin"
  local -- mandir="$PREFIX/share/man/man1"
  local -- completiondir="$PREFIX/share/bash-completion/completions"

  confirm "Install shlock to $bindir/, manpage to $mandir/, and completion to $completiondir/?" || \
    die 1 'Installation cancelled'

  install_script
  install_manpage
  install_completion

  echo
  echo 'Installation complete!'
  echo "  Script: $bindir/$SCRIPT"
  echo "  Manpage: $mandir/$TARGET"
  echo "  Completion: $completiondir/$COMPLETION_DEST"
  echo
  echo 'Usage: shlock [OPTIONS] [LOCKNAME] -- COMMAND [ARGS...]'
  echo 'View manpage: man shlock'
  echo 'Bash completion will be available after restarting your shell'

  # Check if PATH/MANPATH needs updating
  if [[ "$PREFIX" != "/usr" && "$PREFIX" != "/usr/local" ]]; then
    echo
    echo 'Note: Custom prefix detected. You may need to update PATH and MANPATH:'
    echo "  export PATH=\"$PREFIX/bin:\$PATH\""
    echo "  export MANPATH=\"$PREFIX/share/man:\$MANPATH\""
  fi
}

# Uninstall the script
uninstall_script() {
  local -- bindir="$PREFIX/bin"
  local -- script_path="$bindir/$SCRIPT"
  [[ -f "$script_path" ]] || die 1 "Script not found at $script_path"
  echo "Removing script from $script_path"
  rm -f "$script_path" || die 1 'Failed to remove script (try with sudo?)'
  echo '✓ Script removed'
}

# Uninstall the manpage
uninstall_manpage() {
  local -- mandir="$PREFIX/share/man/man1"
  local -- target_path="$mandir/$TARGET"
  [[ -f "$target_path" ]] || die 1 "Manpage not found at $target_path"
  echo "Removing manpage from $target_path"
  rm -f "$target_path" || die 1 'Failed to remove manpage (try with sudo?)'
  echo 'Updating man database...'
  mandb -q 2>/dev/null ||:
  echo '✓ Manpage removed'
}

# Uninstall the bash completion
uninstall_completion() {
  local -- completiondir="$PREFIX/share/bash-completion/completions"
  local -- completion_path="$completiondir/$COMPLETION_DEST"
  [[ -f "$completion_path" ]] || die 1 "Completion not found at $completion_path"
  echo "Removing bash completion from $completion_path"
  rm -f "$completion_path" || die 1 'Failed to remove completion (try with sudo?)'
  echo '✓ Bash completion removed'
}

# Uninstall script, manpage, and completion
uninstall_all() {
  local -- bindir="$PREFIX/bin"
  local -- mandir="$PREFIX/share/man/man1"
  local -- completiondir="$PREFIX/share/bash-completion/completions"
  local -- script_path="$bindir/$SCRIPT"
  local -- man_path="$mandir/$TARGET"
  local -- completion_path="$completiondir/$COMPLETION_DEST"

  if [[ ! -f "$script_path" && ! -f "$man_path" && ! -f "$completion_path" ]]; then
    die 1 "shlock not found in $PREFIX"
  fi

  confirm "Remove shlock from $bindir/, $mandir/, and $completiondir/?" || \
    die 1 'Uninstall cancelled'

  if [[ -f "$script_path" ]]; then uninstall_script; else echo 'Script not installed, skipping'; fi
  if [[ -f "$man_path" ]]; then uninstall_manpage; else echo 'Manpage not installed, skipping'; fi
  if [[ -f "$completion_path" ]]; then uninstall_completion; else echo 'Completion not installed, skipping'; fi

  echo
  echo 'Uninstall complete'
}

# Clean generated files
clean_files() {
  echo 'Cleaning generated files'
  if [[ -f "$TARGET" ]]; then
    rm -f "$TARGET"
    echo "✓ Removed $TARGET"
  else
    echo 'Nothing to clean (no generated files found)'
  fi
}

# Main function
main() {
  while (($#)); do
    case $1 in
      --prefix)
        shift
        [[ -n "${1:-}" ]] || die 2 '--prefix requires a directory argument'
        PREFIX=$1
        ;;
      -y|--yes)
        SKIP_CONFIRM=1
        ;;
      -h|--help)
        show_usage
        exit 0
        ;;
      -V|--version)
        echo "$SCRIPT_NAME $VERSION"
        exit 0
        ;;
      build|install|install-script|install-man|install-completion|uninstall|uninstall-script|uninstall-man|uninstall-completion|clean)
        ACTION=$1
        ;;
      --)
        shift
        break
        ;;
      -*)
        die 2 "Unknown option: ${1@Q}"
        ;;
      *)
        die 2 "Unknown action: ${1@Q}"
        ;;
    esac
    shift
  done

  # Expand PREFIX to absolute path
  PREFIX=$(cd "$PREFIX" 2>/dev/null && pwd) || {
    PREFIX=$(realpath -m "$PREFIX" 2>/dev/null) || die 2 "Invalid prefix: ${PREFIX@Q}"
  }

  readonly -- PREFIX SKIP_CONFIRM ACTION

  # Execute action
  case $ACTION in
    build)
      build_manpage
      ;;
    install)
      install_all
      ;;
    install-script)
      confirm "Install script to $PREFIX/bin/?" || die 1 'Installation cancelled'
      install_script
      echo
      echo "Script installed: $PREFIX/bin/$SCRIPT"
      ;;
    install-man)
      confirm "Install manpage to $PREFIX/share/man/man1/?" || die 1 'Installation cancelled'
      install_manpage
      echo
      echo "Manpage installed: $PREFIX/share/man/man1/$TARGET"
      echo 'View with: man shlock'
      ;;
    install-completion)
      confirm "Install bash completion to $PREFIX/share/bash-completion/completions/?" || die 1 'Installation cancelled'
      install_completion
      echo
      echo "Bash completion installed: $PREFIX/share/bash-completion/completions/$COMPLETION_DEST"
      echo 'Restart your shell to enable completion'
      ;;
    uninstall)
      uninstall_all
      ;;
    uninstall-script)
      confirm "Remove script from $PREFIX/bin/?" || die 1 'Uninstall cancelled'
      uninstall_script
      ;;
    uninstall-man)
      confirm "Remove manpage from $PREFIX/share/man/man1/?" || die 1 'Uninstall cancelled'
      uninstall_manpage
      ;;
    uninstall-completion)
      confirm "Remove bash completion from $PREFIX/share/bash-completion/completions/?" || die 1 'Uninstall cancelled'
      uninstall_completion
      ;;
    clean)
      clean_files
      ;;
    *)
      die 2 "Unknown action: ${ACTION@Q}"
      ;;
  esac
}

main "$@"

#fin
