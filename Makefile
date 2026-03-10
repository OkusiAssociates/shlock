# Makefile - Install shlock
# BCS1212 compliant

PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
MANDIR  ?= $(PREFIX)/share/man/man1
COMPDIR ?= /etc/bash_completion.d
DESTDIR ?=

.PHONY: all install uninstall check build clean help

all: help

build: shlock.1

shlock.1: shlock.1.md
	pandoc --standalone --to man -o shlock.1 shlock.1.md

install: build
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 shlock $(DESTDIR)$(BINDIR)/shlock
	install -d $(DESTDIR)$(MANDIR)
	install -m 644 shlock.1 $(DESTDIR)$(MANDIR)/shlock.1
	@if [ -d $(DESTDIR)$(COMPDIR) ]; then \
	  install -m 644 shlock.bash_completion $(DESTDIR)$(COMPDIR)/shlock; \
	fi
	@if [ -z "$(DESTDIR)" ]; then $(MAKE) --no-print-directory check; fi

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/shlock
	rm -f $(DESTDIR)$(MANDIR)/shlock.1
	rm -f $(DESTDIR)$(COMPDIR)/shlock

check:
	@command -v shlock >/dev/null 2>&1 \
	  && echo 'shlock: OK' \
	  || echo 'shlock: NOT FOUND (check PATH)'

clean:
	rm -f shlock.1

help:
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@echo '  install     Install to $(PREFIX) (builds manpage first)'
	@echo '  uninstall   Remove installed files'
	@echo '  check       Verify installation'
	@echo '  build       Build manpage from shlock.1.md'
	@echo '  clean       Remove generated files'
	@echo '  help        Show this message'
	@echo ''
	@echo 'Install from GitHub:'
	@echo '  git clone https://github.com/Open-Technology-Foundation/shlock.git'
	@echo '  cd shlock && sudo make install'
