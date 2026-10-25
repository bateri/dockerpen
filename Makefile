# dockerpen is one native file: pencere's Lua runner with the program (src/program/), the page
# (src/view/page.lua) and the pictures (src/assets/) packed into it. The gate and the steps of a
# release are here; RELEASING.md says in what order and why.
.PHONY: check fmt lint build test test-page test-binary dist release-prepare release publish

# `pencere` is the command of a pencere checkout, built there (cargo build --release -p
# pencere-cli); the stand-in terminal the end-to-end tests play dockerpen in is built there too
# (cargo build -p pencere-fake-host). Where they are not, say so:
#
#   make check PENCERE=../pencere-lua/target/release/pencere \
#              FAKE_HOST=../pencere-lua/target/debug/pencere-fake-host
PENCERE ?= ../pencere/target/release/pencere
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
	@test -x "$(PENCERE)" || { echo "build: the pencere command is not at $(PENCERE): build it in a pencere checkout (cargo build --release -p pencere-cli), then make build PENCERE=<it>"; exit 1; }
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

test: test-page test-binary

# check is the gate: formatting, the program built, the page's tests and the built program held
# to what the page expects of it.
check: lint build test

# dist makes the program for the three targets dockerpen ships (Apple silicon Macs and both Linux
# architectures; bateri, the terminal that shows the view, runs on Apple silicon only) into
# dist/release, with the SHA256SUMS that names them. The runners come from a pencere checkout's
# `make dist` (RUNNERS=<its dist/>), one for each target, of the version of the `pencere` command.
# When pencere has a release, `pencere build --target T` fetches them itself and --runner goes
# away.
TARGETS = aarch64-apple-darwin aarch64-unknown-linux-musl x86_64-unknown-linux-musl
RUNNERS ?= ../pencere/dist
PACKAGE_VERSION = $(shell node tools/release.mjs version)
RUNNER_VERSION = $(shell "$(PENCERE)" --version | sed 's/^pencere //')

dist:
	@test -x "$(PENCERE)" || { echo "dist: the pencere command is not at $(PENCERE): see PENCERE at the top of the Makefile"; exit 1; }
	rm -rf dist/release
	mkdir -p dist/release
	@for target in $(TARGETS); do \
		runner="$(RUNNERS)/pencere-$(RUNNER_VERSION)-$$target"; \
		test -f "$$runner" || { echo "dist: no runner for $$target at $$runner: make dist in a pencere checkout, then make dist RUNNERS=<its dist/>"; exit 1; }; \
		"$(PENCERE)" build --name dockerpen --target $$target --runner "$$runner" -o dist/release/dockerpen-$(PACKAGE_VERSION)-$$target || exit 1; \
	done
	cd dist/release && shasum -a 256 dockerpen-* > SHA256SUMS
	@cat dist/release/SHA256SUMS

# release-prepare sets the version and dates the changelog's Unreleased section.
release-prepare:
	@test -n "$(VERSION)" || { echo "usage: make release-prepare VERSION=<x.y.z>"; exit 2; }
	node tools/release.mjs prepare $(VERSION)

# release runs the gate and the release checks (dist/release holds the three files of this
# version, made after the release commit), then tags. Nothing is pushed.
release: check
	node tools/release.mjs tag

# publish pushes main and the tag, then makes the GitHub release with the three files and
# SHA256SUMS. Publishing: run on the maintainer's word.
publish:
	node tools/release.mjs publish
