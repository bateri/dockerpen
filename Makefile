# dockerpen is one native file: pencere's Lua runner with the program (src/program/), the page
# (src/view/page.lua) and the pictures (src/assets/) packed into it. The gate and the steps of a
# release are here; RELEASING.md says in what order and why.
.PHONY: check fmt lint build dev test test-page test-binary test-tools release-prepare release publish

# What dockerpen ships: macOS on Apple silicon and Linux on both architectures (bateri, the terminal
# that shows the view, runs on Apple silicon only). The pencere it is built, tested and released
# with (pencere, fake-host, pencere-ref) and the files of its release (dist, sums) are tools/pen.mk.
NAME = dockerpen
TARGETS = aarch64-apple-darwin aarch64-unknown-linux-musl x86_64-unknown-linux-musl
PACKAGE_VERSION = $(shell node tools/release.mjs version)
.DEFAULT_GOAL := check
include tools/pen.mk

# The Lua files are formatted with StyLua (cargo install stylua --locked --features luau).
STYLUA ?= stylua

# fmt formats the Lua files.
fmt:
	$(STYLUA) src test

# lint is the formatting, checked.
lint:
	@command -v "$(STYLUA)" >/dev/null || { echo "lint: StyLua is not installed: cargo install stylua --locked --features luau"; exit 1; }
	$(STYLUA) --check src test

# build makes dist/dockerpen, the program for this machine, as one file.
build: pencere
	"$(PENCERE)" build --name $(NAME) -o dist/dockerpen

# dev runs dockerpen from its files in this pane, and again when one of them changes: in a pane of
# a terminal that hosts pencere (bateri). What it prints goes to .pencere/log.
dev: pencere
	"$(PENCERE)" dev --name $(NAME)

# test-page runs the page against the kit's page API, with the program's pieces it leans on, in
# the runner (the page is Lua, and the runner is the Lua there is to run it).
test-page: pencere
	PENCERE="$(PENCERE)" PENCERE_PRELUDE="$(PRELUDE)" node --test test/lua.test.mjs

# test-binary runs the program, dist/dockerpen (DOCKERPEN_BIN, a file of a release too), in a pane
# under the stand-in terminal, with a stand-in docker: the calls and topics of the page. Nothing in
# it is skipped; a program or a stand-in that is not there stops the run.
DOCKERPEN_BIN ?= dist/dockerpen
test-binary: pencere fake-host
	PENCERE_FAKE_HOST="$(FAKE_HOST)" DOCKERPEN_BIN="$(DOCKERPEN_BIN)" node --test test/program.test.mjs

# test-tools runs the tests of the installer (install.sh), against a stand-in for GitHub, and of the
# release checks (tools/release-files.mjs), against a directory of their own.
test-tools:
	node --test test/install.test.mjs test/release.test.mjs

test: test-page test-binary test-tools

# check is the gate: formatting, the program built, the page's tests and the built program held
# to what the page expects of it.
check: lint build test

# release-prepare sets the version and dates the changelog's Unreleased section.
release-prepare:
	@test -n "$(VERSION)" || { echo "usage: make release-prepare VERSION=<x.y.z>"; exit 2; }
	node tools/release.mjs prepare $(VERSION)

# release runs the gate and the release checks (dist/release holds the three files of this
# version, SHA256SUMS, app.json and its signature, made after the release commit), then tags.
# Nothing is pushed.
release: check
	node tools/release.mjs tag

# publish pushes main and the tag, then makes the GitHub release with the three files, SHA256SUMS,
# app.json and app.json.sig. Publishing: run on the maintainer's word.
publish:
	node tools/release.mjs publish
