# Releasing

dockerpen is released as five files on a GitHub release tagged `v<x.y.z>` here: the program for
macOS on Apple silicon (`arm64`) and for Linux on `arm64` and `x86_64`, named
`dockerpen-<version>-<target>`, a `SHA256SUMS` that names the three, and an `app.json` with its
signature `app.json.sig`, which a terminal that follows dockerpen reads (pencere's `apps.md`). There
is no Intel Mac file: bateri, the terminal that shows the page, runs on Apple silicon only.
Every step a machine can check is in `tools/release.mjs`, behind the `make` targets below. This
file is the order of the steps and the reasons for them.

## Versions and the changelog

dockerpen follows [semantic versioning](https://semver.org/). While it is `0.x`, a minor release
may change what the previous one did.

Every change a user would notice goes under `## [Unreleased]` in `CHANGELOG.md`
([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)), in the same commit as the change. A
release only moves that section under a version and a date; it does not write it.

## What a release needs

Each of the three files is pencere's Lua runner for one target with dockerpen's program
(`src/program/`), page (`src/view/`) and pictures (`src/assets/`) packed into it by `pencere build`.
Both come from the pencere that `tools/pencere-ref` names, the one the gate tests against: to release
with a newer pencere, move the pin (`make pencere-pin`, the head of pencere's `main`). So a release
needs:

- A Mac on Apple silicon, with Rust 1.99 (the toolchain the gate runs with, from rustup, with the
  `aarch64-apple-darwin` standard library) and Docker. All three files are made on that one
  machine: the Mac runner by cargo, the two Linux runners (static musl executables) in pencere's
  own Docker image, the `x86_64` one emulated, slow the first time. The runners are built into
  `dist/runners` and kept there, for the commit of pencere that built them; a pin that moves builds
  them again. Docker is used to build and to check them, and nothing in it is removed.
- Node, for `tools/release.mjs`: it is the one step of a release that is not `make`'s.
- `gh`, logged in, to make the GitHub release.
- The signing key, on the maintainer's machine: `app.json` is signed with the key `pencere key`
  makes, kept in `~/.config/pencere/signing.key` (`PENCERE_SIGNING_KEY` names another file). It is
  the "bateri" key, the one bateri carries the public half of to follow dockerpen without asking:
  whoever has the file can release as dockerpen, so it is never committed and never on a machine
  that builds in a workflow, and it has a copy somewhere safe. A release signed with another key
  is a release bateri asks its people about.
- A `pencere` command that has `dist`, the one `tools/pencere-ref` names: `make pencere` builds it
  (`PENCERE` names another).

The files are built on the maintainer's machine and not by a workflow: an executable that a
workflow built is one that a pushed tag changes without a maintainer's decision. CI runs the gate
(`make check`) on Linux and macOS on every push and pull request; a release runs it again here.

## A release

From a clean `main`:

1. `make release-prepare VERSION=0.6.0` sets the version in `src/program/version.lua` (the program
   says that version: `dockerpen --version`), and turns `## [Unreleased]` into
   `## [0.6.0] - <today>` with a new, empty `## [Unreleased]` above it. Read the diff, then commit
   it as `Release dockerpen 0.6.0`.
2. From that commit, on a clean tree: `make dist TARGET=<target>` for each target, which builds
   `dist/release/dockerpen-0.6.0-<target>` (the runner of the target first, if `dist/runners` has
   none of this pencere), or `make dist` for the three. Then `make sums` writes `SHA256SUMS`, and
   with `pencere dist` the `app.json` and `app.json.sig`: what the program needs of a terminal is
   not typed, `pencere dist` starts the file of this machine's target and reads what it says, and
   the earlier releases that `app.json` lists come from the `app.json` of the release before (the
   latest on GitHub; `DIST_FLAGS="--previous <file>"` names another, `--previous none` is for a
   first release). The file names carry the version, so a `dist/release` built before the version
   moved is refused; nothing can tell which source a file of the right version was built from, so
   build them after the commit and not before.
3. `make release` runs the gate (`make check`), then the release checks, then makes the annotated
   tag `v0.6.0` with the changelog section as its message. Nothing is pushed.
4. `make publish` pushes `main` and the tag in one atomic push, then makes the GitHub release
   with the changelog section as its notes and the five files.
5. Check it: `gh release view v0.6.0`, and run `install.sh` on a machine.

If a check fails, nothing has left the machine: fix it, amend or add a commit, and run the step
again. A tag that was made but not pushed can be deleted with `git tag -d <tag>`. A pushed tag is
never moved; a broken release is followed by a new version. If the push went and `gh` failed, the
tag is on `origin` and the release is not: make it by hand with `gh release create v0.6.0
--verify-tag` and the files of `dist/release`.

### What the release checks refuse

- a version that is not after the last, or a `src/program/version.lua` that disagrees with the
  newest changelog section, or a `tools/pencere-ref` that is not one commit of pencere, whole;
- an `## [Unreleased]` section that still holds changes, or an empty release section;
- a branch other than `main`, a working tree that is not clean, a `main` that has diverged from
  `origin/main`;
- a tag that already exists, here or on `origin`, or a release that already exists on GitHub;
- a `dist/release` that is not exactly the three files of this version, `SHA256SUMS`, `app.json` and
  `app.json.sig`, with the sum of each as listed, or whose executable for this machine does not say
  this version;
- an `app.json` that its signature does not belong to (by the key it names), that is signed with
  another key than the "bateri" key (a published release cannot be taken back, and every bateri
  would turn it away), that is of another app or version, that does not name exactly the three
  targets at addresses ending in the files' names, or whose sums are not those of `SHA256SUMS`.

## Who releases

`make publish` makes the release under the project's name. Only a maintainer runs it. Everything
before it (prepare, commit, dist, tag) can be undone locally.

## The old npm package

dockerpen 0.2.1, the Node program, is on npm and is no longer updated. To point its users here, a
maintainer runs once (npm asks for the second factor):

```sh
npm deprecate dockerpen "dockerpen is now a single native file, without Node: take it from https://github.com/bateri/dockerpen/releases"
```
