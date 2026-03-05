# Makefile for shlock
#
# Builds and installs the shlock script, manpage, and bash completion
#
# Targets:
#   all                - Build shlock.1 from shlock.1.md (default)
#   build              - Same as all
#   install            - Install script, manpage, and completion
#   install-script     - Install only the shlock script
#   install-man        - Install only the manpage
#   install-completion - Install only the bash completion
#   uninstall          - Remove script, manpage, and completion
#   uninstall-script   - Remove only the script
#   uninstall-man      - Remove only the manpage
#   uninstall-completion - Remove only the bash completion
#   clean              - Remove generated shlock.1
#   check-deps         - Verify pandoc is installed
#   help               - Show this help message

# Installation prefix (override with: make PREFIX=/usr install)
PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/share/man/man1
COMPLETIONDIR = $(PREFIX)/share/bash-completion/completions

# Tools
PANDOC = pandoc
INSTALL = install
RM = rm -f
MKDIR = mkdir -p

# Files
SCRIPT = shlock
SOURCE = shlock.1.md
TARGET = shlock.1
COMPLETION_SRC = shlock.bash_completion
COMPLETION_DEST = shlock

# Pandoc options for manpage generation
PANDOC_OPTS = --standalone --to man

# PHONY targets (not actual files)
.PHONY: all build install install-script install-man install-completion uninstall uninstall-script uninstall-man uninstall-completion clean check-deps help

# Default target
all: build

# Build the manpage from markdown source
build: check-deps $(TARGET)

$(TARGET): $(SOURCE)
	@echo "Building manpage: $(TARGET)"
	$(PANDOC) $(PANDOC_OPTS) -o $(TARGET) $(SOURCE)
	@echo "Manpage built successfully"

# Check if pandoc is installed
check-deps:
	@command -v $(PANDOC) >/dev/null 2>&1 || { \
		echo "Error: pandoc is not installed" >&2; \
		echo "Install with: sudo apt install pandoc (Debian/Ubuntu)" >&2; \
		echo "           or: sudo dnf install pandoc (Fedora/RHEL)" >&2; \
		echo "           or: brew install pandoc (macOS)" >&2; \
		exit 1; \
	}
	@echo "Dependency check passed: pandoc is installed"

# Install script, manpage, and completion
install: install-script install-man install-completion
	@echo ""
	@echo "Installation complete!"
	@echo "  Script: $(BINDIR)/$(SCRIPT)"
	@echo "  Manpage: $(MANDIR)/$(TARGET)"
	@echo "  Completion: $(COMPLETIONDIR)/$(COMPLETION_DEST)"
	@echo ""
	@echo "Usage: shlock [OPTIONS] [LOCKNAME] -- COMMAND [ARGS...]"
	@echo "View manpage: man shlock"
	@echo "Bash completion will be available after restarting your shell"

# Install only the script
install-script:
	@echo "Installing script to $(BINDIR)/$(SCRIPT)"
	$(MKDIR) $(BINDIR)
	$(INSTALL) -m 755 $(SCRIPT) $(BINDIR)/$(SCRIPT)
	@echo "✓ Script installed"

# Install only the manpage
install-man: build
	@echo "Installing manpage to $(MANDIR)/$(TARGET)"
	$(MKDIR) $(MANDIR)
	$(INSTALL) -m 644 $(TARGET) $(MANDIR)/$(TARGET)
	@echo "Updating man database..."
	@mandb -q 2>/dev/null || true
	@echo "✓ Manpage installed"

# Install only the bash completion
install-completion:
	@echo "Installing bash completion to $(COMPLETIONDIR)/$(COMPLETION_DEST)"
	$(MKDIR) $(COMPLETIONDIR)
	$(INSTALL) -m 644 $(COMPLETION_SRC) $(COMPLETIONDIR)/$(COMPLETION_DEST)
	@echo "✓ Bash completion installed"

# Uninstall script, manpage, and completion
uninstall: uninstall-script uninstall-man uninstall-completion
	@echo ""
	@echo "Uninstall complete"

# Uninstall only the script
uninstall-script:
	@echo "Removing script from $(BINDIR)/$(SCRIPT)"
	$(RM) $(BINDIR)/$(SCRIPT)
	@echo "✓ Script removed"

# Uninstall only the manpage
uninstall-man:
	@echo "Removing manpage from $(MANDIR)/$(TARGET)"
	$(RM) $(MANDIR)/$(TARGET)
	@echo "Updating man database..."
	@mandb -q 2>/dev/null || true
	@echo "✓ Manpage removed"

# Uninstall only the bash completion
uninstall-completion:
	@echo "Removing bash completion from $(COMPLETIONDIR)/$(COMPLETION_DEST)"
	$(RM) $(COMPLETIONDIR)/$(COMPLETION_DEST)
	@echo "✓ Bash completion removed"

# Remove generated files
clean:
	@echo "Cleaning generated files"
	$(RM) $(TARGET)
	@echo "Clean complete"

# Show help message
help:
	@echo "shlock Makefile targets:"
	@echo ""
	@echo "  make                     - Build manpage (default)"
	@echo "  make build               - Build manpage from $(SOURCE)"
	@echo "  make install             - Install script, manpage, and completion"
	@echo "  make install-script      - Install only the script"
	@echo "  make install-man         - Install only the manpage"
	@echo "  make install-completion  - Install only bash completion"
	@echo "  make uninstall           - Remove script, manpage, and completion"
	@echo "  make uninstall-script    - Remove only the script"
	@echo "  make uninstall-man       - Remove only the manpage"
	@echo "  make uninstall-completion - Remove only bash completion"
	@echo "  make clean               - Remove generated $(TARGET)"
	@echo "  make check-deps          - Verify pandoc is installed"
	@echo "  make help                - Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX=$(PREFIX)  - Installation prefix"
	@echo "  BINDIR=$(BINDIR)  - Script installation directory"
	@echo "  MANDIR=$(MANDIR)  - Manpage installation directory"
	@echo "  COMPLETIONDIR=$(COMPLETIONDIR)  - Bash completion directory"
	@echo ""
	@echo "Examples:"
	@echo "  make install                 - Install to $(PREFIX)"
	@echo "  make PREFIX=/usr install     - Install to /usr"
	@echo "  make PREFIX=~/.local install - Install to ~/.local"
	@echo "  make install-script          - Install only the script"
	@echo "  make install-man             - Install only the manpage"
	@echo "  make install-completion      - Install only bash completion"
