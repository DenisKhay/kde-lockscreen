VERSION := 0.1.1
NAME    := kde-lockscreen

.PHONY: help install install-dev uninstall test preview dist clean version

help:
	@echo "kde-lockscreen — make targets"
	@echo ""
	@echo "  make install       — full install (LNF package + daemon venv + systemd + PAM prompt)"
	@echo "  make install-dev   — copy package, skip venv / systemd / PAM (fast iteration)"
	@echo "  make uninstall     — revert everything (theme, units, PAM backup)"
	@echo "  make test          — run daemon pytest suite"
	@echo "  make preview       — launch the greeter in a test window (no real lock)"
	@echo "  make dist          — build $(NAME)-$(VERSION).tar.gz release tarball"
	@echo "  make version       — print version"

version:
	@echo $(VERSION)

install:
	./scripts/install.sh

install-dev:
	./scripts/install-dev.sh

uninstall:
	./scripts/uninstall.sh

test:
	cd daemon && python3 -m venv .venv >/dev/null 2>&1 || true
	cd daemon && .venv/bin/pip install -q -e '.[dev]'
	cd daemon && .venv/bin/pytest tests/ -v

preview:
	./scripts/test-greeter.sh

dist:
	@echo ">> Building $(NAME)-$(VERSION).tar.gz"
	@tar --exclude-vcs --exclude='daemon/.venv' --exclude='__pycache__' \
	     --exclude='.pytest_cache' --exclude='*.egg-info' \
	     --transform 's,^,$(NAME)-$(VERSION)/,' \
	     -czf $(NAME)-$(VERSION).tar.gz \
	     LICENSE README.md Makefile package/ daemon/ systemd/ pam/ scripts/ docs/
	@echo ">> Wrote $(NAME)-$(VERSION).tar.gz ($$(du -h $(NAME)-$(VERSION).tar.gz | cut -f1))"

clean:
	rm -f $(NAME)-*.tar.gz
	rm -rf daemon/.venv daemon/*.egg-info
	find . -type d -name '__pycache__' -exec rm -rf {} +
	find . -type d -name '.pytest_cache' -exec rm -rf {} +
