# dockerpen is one native file: pencere's Lua runner with the program (src/program/), the page
# (src/view/page.lua) and the pictures (src/assets/) packed into it. The gate and the steps of a
# release are here; RELEASING.md says in what order and why.
.PHONY: check fmt lint pencere build dev test test-page test-binary test-tools dist release-prepare rehearse

# pencere is what dockerpen is built and tested with: its `pencere` command (the runner the program
# is packed into), its stand-in terminal the end-to-end tests play dockerpen in (pencere-fake-host)
# and the prelude of its kit, the page API the page's tests run the page against. All three come
# from one checkout of pencere, PENCERE_SRC, and are built there by `make pencere`, which the steps
# that need them run first.
#
# By default it is pencere at the commit or release tag in tools/pencere-ref, fetched into
# .cache/pencere: the gate holds dockerpen to that pencere and nothing else, on any machine. To work
# against another checkout, a pencere you are changing, say so; a checkout that is not at
# tools/pencere-ref is said to be so:
#
#   make dev PENCERE_SRC=../pencere
PENCERE_REF := $(shell cat tools/pencere-ref)
PENCERE_CACHE = .cache/pencere
PENCERE_SRC ?= $(PENCERE_CACHE)
PENCERE ?= $(PENCERE_SRC)/target/release/pencere
FAKE_HOST ?= $(PENCERE_SRC)/target/release/pencere-fake-host
PRELUDE ?= $(PENCERE_SRC)/kit/luau/prelude
PENCERE_GIT = https://github.com/bateri/pencere

# The Lua files are formatted with StyLua (cargo install stylua --locked --features luau).
STYLUA ?= stylua

# fmt formats the Lua files.
fmt:
	$(STYLUA) src test

# lint is the formatting, checked.
lint:
	@command -v "$(STYLUA)" >/dev/null || { echo "lint: StyLua is not installed: cargo install stylua --locked --features luau"; exit 1; }
	$(STYLUA) --check src test

# pencere makes PENCERE_SRC ready: fetched at tools/pencere-ref when it is the cache, and the
# command and the stand-in terminal built there, so that they are what its prelude is. The cache is
# one checkout, moved to another ref when the file moves, so that cargo builds again only what
# changed.
pencere:
	@command -v cargo >/dev/null || { echo "pencere: cargo is not installed: pencere is built from its source (https://rustup.rs)"; exit 1; }
	@if [ "$(PENCERE_SRC)" = "$(PENCERE_CACHE)" ]; then \
		if [ "$$(cat $(PENCERE_CACHE).ref 2>/dev/null)" != "$(PENCERE_REF)" ]; then \
			echo "pencere: fetching $(PENCERE_GIT) at $(PENCERE_REF) into $(PENCERE_CACHE)"; \
			{ test -d "$(PENCERE_CACHE)/.git" || git init -q "$(PENCERE_CACHE)"; } && \
			git -C "$(PENCERE_CACHE)" fetch -q --depth 1 "$(PENCERE_GIT)" "$(PENCERE_REF)" && \
			git -C "$(PENCERE_CACHE)" checkout -q --detach --force FETCH_HEAD && \
			echo "$(PENCERE_REF)" > "$(PENCERE_CACHE).ref" || exit 1; \
		fi; \
	else \
		head=$$(git -C "$(PENCERE_SRC)" rev-parse HEAD 2>/dev/null); \
		want=$$(git -C "$(PENCERE_SRC)" rev-parse -q --verify "$(PENCERE_REF)^{commit}" 2>/dev/null); \
		[ -n "$$head" ] && [ "$$head" = "$$want" ] || \
			echo "pencere: $(PENCERE_SRC) is at $${head:-no commit}, not at $(PENCERE_REF) (tools/pencere-ref) that the gate holds dockerpen to"; \
	fi
	cd "$(PENCERE_SRC)" && cargo build --release -p pencere-cli -p pencere-fake-host

# build makes dist/dockerpen, the program for this machine, as one file.
build: pencere
	"$(PENCERE)" build --name dockerpen -o dist/dockerpen

# dev runs dockerpen from its files in this pane, and again when one of them changes: in a pane of
# a terminal that hosts pencere (bateri). What it prints goes to .pencere/log.
dev: pencere
	"$(PENCERE)" dev --name dockerpen

# test-page runs the page against the kit's page API, with the program's pieces it leans on, in
# the runner (the page is Lua, and the runner is the Lua there is to run it).
test-page: pencere
	PENCERE="$(PENCERE)" PENCERE_PRELUDE="$(PRELUDE)" node --test test/lua.test.mjs

# test-binary runs the program, dist/dockerpen, in a pane under the stand-in terminal, with a
# stand-in docker: the calls and topics of the page. Nothing in it is skipped; a program or a
# stand-in that is not there stops the run.
test-binary: pencere
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
# dist/release, with the SHA256SUMS that names them. They are built with the released `pencere`
# command of the release tools/pencere-ref names, never with a checkout's: `pencere build --target`
# fetches the runner of each target from the release of the command's own version and checks it
# against that release's sums, so no target's toolchain is needed here, and a command built from a
# commit would pack dockerpen into the runners of a release older than the kit it is written for.
# While tools/pencere-ref names a commit there is no release (`tools/release.mjs pencere-version`
# says so). The release workflow installs the command and runs it: make dist PENCERE=<it>.
TARGETS = aarch64-apple-darwin aarch64-unknown-linux-musl x86_64-unknown-linux-musl
PACKAGE_VERSION = $(shell node tools/release.mjs version)

dist:
	@node tools/release.mjs pencere-version >/dev/null
	@test -x "$(PENCERE)" || { echo "dist: the pencere command is not at $(PENCERE): make dist PENCERE=<the released command of tools/pencere-ref>"; exit 1; }
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
