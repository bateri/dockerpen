# dockerpen is one native file: pencere's Lua runner with the program (src/program/), the page
# (src/view/page.lua) and the pictures (src/assets/) packed into it. The gate and the steps of a
# release are here; RELEASING.md says in what order and why.
.PHONY: check fmt lint build test test-page test-binary test-tools dist release-prepare rehearse

# `pencere` is the command that builds dockerpen: a release of it, which pencere's installer puts in
# ~/.local/bin (curl -fsSL https://raw.githubusercontent.com/bateri/pencere/main/cli/install.sh | sh;
# PENCERE_VERSION=<it> for the version in tools/pencere-version, the one releases are built with),
# or one built in a pencere checkout (cargo build --release -p pencere-cli). The stand-in terminal
# the end-to-end tests play dockerpen in has no release: it is built in a pencere checkout (cargo
# build -p pencere-fake-host). Where they are not where the Makefile looks, say so:
#
#   make check PENCERE=../pencere/target/release/pencere \
#              FAKE_HOST=../pencere/target/debug/pencere-fake-host
PENCERE ?= $(shell command -v pencere 2>/dev/null || echo ../pencere/target/release/pencere)
FAKE_HOST ?= ../pencere/target/debug/pencere-fake-host
# The Lua files are formatted with StyLua (cargo install stylua --locked --features luau).
STYLUA ?= stylua
# Where the kit's own page API is, which the page's tests run the page against: the prelude of a
# pencere checkout, the same Lua a terminal gives a page.
PRELUDE ?= ../pencere/kit/luau/prelude

# fmt formats the Lua files.
fmt:
	$(STYLUA) src test

# lint is the formatting, checked.
lint:
	@command -v "$(STYLUA)" >/dev/null || { echo "lint: StyLua is not installed: cargo install stylua --locked --features luau"; exit 1; }
	$(STYLUA) --check src test

# build makes dist/dockerpen, the program for this machine, as one file.
build:
	@test -x "$(PENCERE)" || { echo "build: the pencere command is not at $(PENCERE): install it (see PENCERE at the top of the Makefile), then make build PENCERE=<it>"; exit 1; }
	"$(PENCERE)" build --name dockerpen -o dist/dockerpen

# test-page runs the page against the kit's page API, with the program's pieces it leans on, in
# the runner (the page is Lua, and the runner is the Lua there is to run it).
test-page:
	@test -x "$(PENCERE)" || { echo "test-page: the pencere command is not at $(PENCERE): see PENCERE at the top of the Makefile"; exit 1; }
	PENCERE="$(PENCERE)" PENCERE_PRELUDE="$(PRELUDE)" node --test test/lua.test.mjs

# test-binary runs the program, dist/dockerpen, in a pane under the stand-in terminal, with a
# stand-in docker: the calls and topics of the page. Nothing in it is skipped; a program or a
# stand-in that is not there stops the run.
test-binary:
	@test -x "$(FAKE_HOST)" || { echo "test-binary: pencere-fake-host is not at $(FAKE_HOST): build it in a pencere checkout (cargo build -p pencere-fake-host), then make check FAKE_HOST=<it>"; exit 1; }
	PENCERE_FAKE_HOST="$(FAKE_HOST)" DOCKERPEN_BIN=dist/dockerpen node --test test/program.test.mjs

# test-tools runs the tests of the installer (install.sh) against a stand-in for GitHub.
test-tools:
	node --test test/install.test.mjs

test: test-page test-binary test-tools

# check is the gate: formatting, the program built, the page's tests and the built program held
# to what the page expects of it.
check: lint build test

# dist makes the program for the three targets dockerpen ships (Apple silicon Macs and both Linux
# architectures; bateri, the terminal that shows the view, runs on Apple silicon only) into
# dist/release, with the SHA256SUMS that names them. `pencere build --target` fetches the runner of
# each target from the release of the `pencere` command's own version and checks it against that
# release's sums, so no target's toolchain is needed here. The release workflow runs it.
TARGETS = aarch64-apple-darwin aarch64-unknown-linux-musl x86_64-unknown-linux-musl
PACKAGE_VERSION = $(shell node tools/release.mjs version)

dist:
	@test -x "$(PENCERE)" || { echo "dist: the pencere command is not at $(PENCERE): see PENCERE at the top of the Makefile"; exit 1; }
	rm -rf dist/release
	mkdir -p dist/release
	@for target in $(TARGETS); do \
		"$(PENCERE)" build --name dockerpen --target $$target -o dist/release/dockerpen-$(PACKAGE_VERSION)-$$target || exit 1; \
	done
	cd dist/release && { sha256sum dockerpen-* 2>/dev/null || shasum -a 256 dockerpen-*; } > SHA256SUMS
	@cat dist/release/SHA256SUMS
	node tools/release.mjs dist dist/release

# release-prepare sets the version and dates the changelog's Unreleased section.
release-prepare:
	@test -n "$(VERSION)" || { echo "usage: make release-prepare VERSION=<x.y.z>"; exit 2; }
	node tools/release.mjs prepare $(VERSION)

# rehearse runs the checks of a release of the prepared version, on any branch. It changes nothing:
# a release is the commit of release-prepare pushed to main, which the release workflow tags,
# builds and drafts once the gate is green, and publishes when a maintainer approves (RELEASING.md).
rehearse:
	node tools/release.mjs rehearse
