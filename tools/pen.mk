# The pencere a pen is built, tested and released with, and the files of its release: the part of
# a pen's Makefile that is the same for every pen written in Lua. The Makefile sets NAME, TARGETS
# (the targets it ships) and PACKAGE_VERSION (the version of the release), then includes it.
#
# pencere is the `pencere` command (the runner the program is packed into), its stand-in terminal
# the end-to-end tests play the pen in (pencere-fake-host) and the prelude of its kit, the page API
# the page's tests run the page against. All of it comes from one checkout of pencere, PENCERE_SRC,
# and is built there by `make pencere`, which the steps that need it run first.
#
# By default it is pencere at the commit in tools/pencere-ref, fetched into .cache/pencere: the pen
# is built, tested and released with that pencere and nothing else, on any machine. To work against
# another checkout, a pencere you are changing, name it; one that is not at tools/pencere-ref is
# said to be so:
#
#   make dev PENCERE_SRC=../pencere
#
# `make pencere-pin` moves the pin to the head of pencere's main (REF=<branch, tag or commit> to
# another).
.PHONY: pencere-src pencere pencere-pin runner runners pack sums dist

PENCERE_GIT = https://github.com/bateri/pencere
PENCERE_REF := $(shell cat tools/pencere-ref)
PENCERE_CACHE = .cache/pencere
PENCERE_SRC ?= $(PENCERE_CACHE)
PENCERE ?= $(PENCERE_SRC)/target/release/pencere
FAKE_HOST ?= $(PENCERE_SRC)/target/release/pencere-fake-host
PRELUDE ?= $(PENCERE_SRC)/kit/luau/prelude
# Where the runners are, one for each target (pencere-<target>), with the commit of pencere each
# was built from beside it (pencere-<target>.commit).
RUNNERS ?= dist/runners
# The file of a release for a target.
RELEASE_FILE = dist/release/$(NAME)-$(PACKAGE_VERSION)-$(1)

# pencere-src makes PENCERE_SRC ready: fetched at tools/pencere-ref when it is the cache, and said
# to be off it when it is a checkout of one's own. The cache is one checkout, moved to another
# commit when the pin moves, so that cargo builds again only what changed.
pencere-src:
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
			echo "pencere: $(PENCERE_SRC) is at $${head:-no commit}, not at $(PENCERE_REF) (tools/pencere-ref)"; \
	fi

# pencere builds the command and the stand-in terminal in PENCERE_SRC, so that they are what its
# prelude is.
pencere: pencere-src
	@command -v cargo >/dev/null || { echo "pencere: cargo is not installed: pencere is built from its source (https://rustup.rs)"; exit 1; }
	cd "$(PENCERE_SRC)" && cargo build --release -p pencere-cli -p pencere-fake-host

# pencere-pin writes into tools/pencere-ref the commit that REF (a branch, a tag or a whole commit
# of pencere; main if none) is at, whole: the pin is always a commit, which a branch is not.
pencere-pin:
	@ref="$(or $(REF),main)"; \
	if printf '%s' "$$ref" | grep -Eqx '[0-9a-f]{40}'; then commit=$$ref; else \
		commit=$$(git ls-remote "$(PENCERE_GIT)" "refs/heads/$$ref" "refs/tags/$$ref" "refs/tags/$$ref^{}" | \
			awk '$$2 ~ /\^\{\}$$/ { peeled = $$1 } { any = $$1 } END { print peeled ? peeled : any }'); \
	fi; \
	[ -n "$$commit" ] || { echo "pencere-pin: $(PENCERE_GIT) has no branch or tag '$$ref' (a commit is named whole)"; exit 1; }; \
	echo "$$commit" > tools/pencere-ref; \
	echo "pencere-pin: tools/pencere-ref is $$commit ($$ref), was $(PENCERE_REF)"

# runner builds the runner of TARGET from PENCERE_SRC into RUNNERS, with pencere's own recipe for
# it (`make runner` there: a Linux one in Docker, a Mac one on Apple silicon).
runner: pencere-src
	@test -n "$(TARGET)" || { echo "usage: make runner TARGET=<one of $(TARGETS)>"; exit 2; }
	mkdir -p "$(RUNNERS)"
	cd "$(PENCERE_SRC)" && env MAKEFLAGS= MAKELEVEL= make runner TARGET="$(TARGET)" OUT="$(abspath $(RUNNERS))/pencere-$(TARGET)"
	git -C "$(PENCERE_SRC)" rev-parse HEAD > "$(RUNNERS)/pencere-$(TARGET).commit"

# runners builds the runner of every one of TARGETS on this machine: on a Mac with Docker, the Linux
# one of the other architecture emulated.
runners:
	@for target in $(TARGETS); do $(MAKE) --no-print-directory runner TARGET=$$target || exit 1; done

# pack packs the pen, by the command of PENCERE_SRC, into the runner of TARGET in RUNNERS, which
# must be of the same commit of pencere: the file of the release for that target.
pack: pencere
	@test -n "$(TARGET)" || { echo "usage: make pack TARGET=<one of $(TARGETS)>"; exit 2; }
	@test -s "$(RUNNERS)/pencere-$(TARGET)" || { echo "pack: no runner for $(TARGET) in $(RUNNERS): make runner TARGET=$(TARGET)"; exit 1; }
	@commit=$$(git -C "$(PENCERE_SRC)" rev-parse HEAD); \
	[ "$$(cat "$(RUNNERS)/pencere-$(TARGET).commit" 2>/dev/null)" = "$$commit" ] || \
		{ echo "pack: the runner for $(TARGET) in $(RUNNERS) is not of pencere $$commit, which packs: make runner TARGET=$(TARGET)"; exit 1; }
	mkdir -p dist/release
	"$(PENCERE)" build --name $(NAME) --target $(TARGET) --runner "$(RUNNERS)/pencere-$(TARGET)" -o $(call RELEASE_FILE,$(TARGET))

# sums writes the SHA256SUMS of the files of a release in dist/release and checks the release: the
# files of every one of TARGETS, each the file the sums list (tools/release.mjs dist).
sums:
	cd dist/release && { sha256sum $(NAME)-* 2>/dev/null || shasum -a 256 $(NAME)-*; } > SHA256SUMS
	@cat dist/release/SHA256SUMS
	node tools/release.mjs dist dist/release

# dist makes the files of a release here, from the runners in RUNNERS (make runners): each target
# packed, then the sums. The release workflow does the same, a target on a machine of its own.
dist:
	rm -rf dist/release
	@for target in $(TARGETS); do $(MAKE) --no-print-directory pack TARGET=$$target || exit 1; done
	@$(MAKE) --no-print-directory sums
