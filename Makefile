# dockerpen is one native file: pencere's Lua runner with the program (src/program/), the page
# (src/view/page.lua) and the pictures (src/assets/) packed into it. The gate and the steps of a
# release are here; RELEASING.md says in what order and why.
.PHONY: check fmt lint build dev test test-page test-binary test-tools release-prepare rehearse

# What dockerpen ships: macOS on Apple silicon and Linux on both architectures (bateri, the terminal
# that shows the view, runs on Apple silicon only). The pencere it is built, tested and released
# with, and how its release is made, are tools/pen.mk.
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
test-binary: pencere
	PENCERE_FAKE_HOST="$(FAKE_HOST)" DOCKERPEN_BIN="$(DOCKERPEN_BIN)" node --test test/program.test.mjs

# test-tools runs the tests of the installer (install.sh) against a stand-in for GitHub.
test-tools:
	node --test test/install.test.mjs

test: test-page test-binary test-tools

# check is the gate: formatting, the program built, the page's tests and the built program held
# to what the page expects of it.
check: lint build test

# release-prepare sets the version and dates the changelog's Unreleased section.
release-prepare:
	@test -n "$(VERSION)" || { echo "usage: make release-prepare VERSION=<x.y.z>"; exit 2; }
	node tools/release.mjs prepare $(VERSION)

# rehearse runs the checks of a release of the prepared version, on any branch. It changes nothing:
# a release is the commit of release-prepare pushed to main, which the release workflow tags,
# builds and drafts once the gate is green, and publishes when a maintainer approves (RELEASING.md).
rehearse:
	node tools/release.mjs rehearse
