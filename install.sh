#!/bin/bash
#bcscheck disable=BCS0701 # intentional: minimal messaging; no _msg infrastructure
#bcscheck disable=BCS0702 # intentional: status to stdout acceptable for installer
#bcscheck disable=BCS0703 # intentional: only error()/die() needed
#bcscheck disable=BCS0705 # intentional: no colour helpers
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
# EXIT CODES (BCS-canonical):
#   0  - Success
#   1  - Installation/uninstall cancelled by user (ERR_GENERAL)
#   3  - File/directory not found (ERR_NOENT)
#   18 - Required dependency missing (ERR_NODEP)
#   22 - Invalid argument or unknown action/option (ERR_INVAL)
#
set -euo pipefail
shopt -s inherit_errexit

declare -r SCRIPT_NAME=${0##*/}
declare -r VERSION='1.0.2'

declare -rx PATH=/usr/local/bin:/usr/bin:/bin

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

EXIT CODES (BCS-canonical):
  0  - Success
  1  - Installation/uninstall cancelled by user
  3  - File/directory not found
  18 - Required dependency missing
  22 - Invalid argument or unknown action/option
EOF
}

# Check if pandoc is installed
check_pandoc() {
  if ! command -v pandoc &>/dev/null; then
    error 'pandoc is not installed'
    error ''
    error 'Install with:'
    error '  Debian/Ubuntu: sudo apt install pandoc'
    error '  Fedora/RHEL:   sudo dnf install pandoc'
    error '  macOS:         brew install pandoc'
    die 18
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

# Validate that option "$1" has a non-flag argument "$2"; die 22 on missing.
# Treats a following token that begins with `-` as "missing" to catch
# `--prefix --yes` where `--yes` was meant as a separate flag, not a value.
noarg() {
  (($# > 1)) && [[ $2 != -* ]] || die 22 "Option ${1@Q} requires an argument"
}

# Build the manpage
build_manpage() {
  echo "Building manpage: $TARGET"
  [[ -f "$SOURCE" ]] || die 3 "Source file $SOURCE not found"
  check_pandoc
  pandoc --standalone --to man -o "$TARGET" "$SOURCE" || \
    die 1 'Failed to build manpage'
  echo "✓ Manpage built successfully: $TARGET"
}

# Install the script
install_script() {
  local -- bindir="$PREFIX/bin"
  [[ -f "$SCRIPT" ]] || die 3 "Script file $SCRIPT not found"
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
  local -- completiondir="$COMPDIR"
  [[ -f "$COMPLETION_SRC" ]] || die 3 "Completion file $COMPLETION_SRC not found"
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
  local -- completiondir="$COMPDIR"

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
  [[ -f "$script_path" ]] || die 3 "Script not found at $script_path"
  echo "Removing script from $script_path"
  rm -f "$script_path" || die 1 'Failed to remove script (try with sudo?)'
  echo '✓ Script removed'
}

# Uninstall the manpage
uninstall_manpage() {
  local -- mandir="$PREFIX/share/man/man1"
  local -- target_path="$mandir/$TARGET"
  [[ -f "$target_path" ]] || die 3 "Manpage not found at $target_path"
  echo "Removing manpage from $target_path"
  rm -f "$target_path" || die 1 'Failed to remove manpage (try with sudo?)'
  echo 'Updating man database...'
  mandb -q 2>/dev/null ||:
  echo '✓ Manpage removed'
}

# Uninstall the bash completion
uninstall_completion() {
  local -- completiondir="$COMPDIR"
  local -- completion_path="$completiondir/$COMPLETION_DEST"
  [[ -f "$completion_path" ]] || die 3 "Completion not found at $completion_path"
  echo "Removing bash completion from $completion_path"
  rm -f "$completion_path" || die 1 'Failed to remove completion (try with sudo?)'
  echo '✓ Bash completion removed'
}

# Uninstall script, manpage, and completion
uninstall_all() {
  local -- bindir="$PREFIX/bin"
  local -- mandir="$PREFIX/share/man/man1"
  local -- completiondir="$COMPDIR"
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
      -P|--prefix)
        noarg "$@"; shift
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
        die 22 "Unknown option: ${1@Q}"
        ;;
      *)
        die 22 "Unknown action: ${1@Q}"
        ;;
    esac
    shift
  done

  # Expand PREFIX to absolute path
  PREFIX=$(cd "$PREFIX" 2>/dev/null && pwd) || {
    PREFIX=$(realpath -m "$PREFIX" 2>/dev/null) || die 22 "Invalid prefix: ${PREFIX@Q}"
  }

  readonly -- PREFIX SKIP_CONFIRM ACTION

  # Completion dir: /etc/bash_completion.d for system prefixes
  # (matches host convention for locally-installed tools; eager-loaded at
  # shell startup); $PREFIX/share/bash-completion/completions otherwise
  # (XDG, user installs, lazy-loaded). Override via COMPDIR env var.
  if [[ -z ${COMPDIR:-} ]]; then
    if [[ $PREFIX == /usr || $PREFIX == /usr/local ]]; then
      COMPDIR=/etc/bash_completion.d
    else
      COMPDIR="$PREFIX/share/bash-completion/completions"
    fi
  fi
  readonly -- COMPDIR

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
      confirm "Install bash completion to $COMPDIR/?" || die 1 'Installation cancelled'
      install_completion
      echo
      echo "Bash completion installed: $COMPDIR/$COMPLETION_DEST"
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
      confirm "Remove bash completion from $COMPDIR/?" || die 1 'Uninstall cancelled'
      uninstall_completion
      ;;
    clean)
      clean_files
      ;;
    *)
      die 22 "Unknown action: ${ACTION@Q}"
      ;;
  esac
}

main "$@"

#fin
