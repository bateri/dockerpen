# Releasing

dockerpen is released as three files on a GitHub release tagged `v<x.y.z>` here: the program for
macOS on Apple silicon (`arm64`) and for Linux on `arm64` and `x86_64`, named
`dockerpen-<version>-<target>`, with a `SHA256SUMS` that names the three. There is no Intel Mac file:
bateri, the terminal that shows the interface, runs on Apple silicon only. It is not published on npm.
People install it with `install.sh`, one line (see the README). Every step a machine can check is
in `tools/release.mjs`, which the release workflow runs. This file is the order of the steps and
the reasons for them.

## Versions and the changelog

dockerpen follows [semantic versioning](https://semver.org/). While it is `0.x`, a minor release
may change what the previous one did.

Every change a user would notice goes under `## [Unreleased]` in `CHANGELOG.md`
([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)), in the same commit as the change. A
release only moves that section under a version and a date; it does not write it.

## What a release is made of

Each of the three files is pencere's Lua runner for one target, with dockerpen's program, its
page and its icons packed into it. The `pencere` command of `tools/pencere-version` makes them:
`pencere build --target` fetches the runner of each target from the release of its own version
and checks it against that release's `SHA256SUMS`, so one Linux machine makes all three, with no
target's toolchain. `make dist` does this, here or in the workflow.

The release workflow (`.github/workflows/release.yml`) builds and publishes, and nothing it makes
is public before a maintainer approves it on GitHub. What a workflow gives that one machine could
not is the provenance (a signed statement of which commit and which workflow built each file),
and a build from nothing that is the same for everyone.

## A release

1. **`make release-prepare VERSION=0.3.0`** sets the version in `src/program/version.lua` (the
   program is one file with no manifest beside it, so it carries its version in its source; the
   `package.json` of this repository is for the tests and has none) and turns `## [Unreleased]` into
   `## [0.3.0] - <today>` with a new, empty `## [Unreleased]` above it. Read the diff, commit it as
   `Release dockerpen 0.3.0`, and push it to `main` (directly or through a pull request).
   `make rehearse` runs the release checks first, on any branch, if you want them before the push.
2. **The gate** (`check.yml`) runs on the push, as on every push to `main`. The release workflow
   starts when it has finished green, and not before.
3. **The release workflow** looks at the version: a commit whose version has a tag `v<version>`
   already ends here. Otherwise it checks the version and the changelog, builds the three files
   (`make dist`), sums, checks and attests them, makes the annotated tag `v0.3.0` with the
   changelog section as its message, pushes it, and writes the GitHub release as a **draft** with
   the section as its notes and the four files. A draft is seen by maintainers only.
4. **A maintainer approves** it in the `release` environment (the run waits with **Review
   deployments**; GitHub notifies the reviewers). The workflow then downloads the draft's files,
   checks them against `SHA256SUMS` and with `gh attestation verify`, and publishes the draft as
   the repository's Latest. Rejected, nothing is published and the draft stays.
5. Check it: `gh release view v0.3.0`, and `install.sh` on a machine:
   `curl -fsSL https://raw.githubusercontent.com/bateri/dockerpen/main/install.sh | sh`.

If a check fails before the tag, nothing has left the repository: fix it in a new commit and push;
the version still has no tag, so the next green gate releases it. A pushed tag is never moved; a
broken release is followed by a new version. A release that stopped after its tag is finished by
starting the workflow by hand on `main` (**Run workflow** in the Actions tab, or `gh workflow run
release.yml`): it asks for the gate's green run on that commit, takes the tag that is there, and
makes the draft again. Started by hand with **rehearse**, on any branch, it only builds and keeps
the files as a workflow artifact.

**The `pencere` command.** `tools/pencere-version` is the version of the `pencere` command that
builds a release and that the gate builds with. A new release of it is taken by changing that
file, in a commit the gate runs.

### What the release checks refuse

- a version that is not after the last, or a `src/program/version.lua` that disagrees with the
  newest changelog section;
- an `## [Unreleased]` section that still holds changes, or an empty release section;
- a commit whose gate is not green on `main` (the workflow starts after it, or asks for it);
- a tag that is on another commit, or a release that is public already;
- files that are not exactly the three executables of this version and `SHA256SUMS`, with the sum
  of each as listed, or, where they are made, an executable for that machine that does not say
  this version; and at the publication, files whose attestation is not this repository's release
  workflow's.

## The npm package

dockerpen 0.2.1 is on npm, as the Node program it was. Nothing is published there any more.
At the first release of the native file, a maintainer deprecates the old package by hand, so
that whoever installs it is told where the files are:

```sh
npm deprecate dockerpen "dockerpen is now a single native file, without Node: take it from https://github.com/bateri/dockerpen/releases"
```

npm asks for the second factor, so run it in a terminal (the log of the publication prints this
command while the package is not deprecated). The trusted publisher set up for `release.yml` on
npmjs.com, if there is one, is removed in the package's settings: no workflow publishes there. None of this is done by a commit that changes the program: it is the maintainer's word,
at the release.

## Settings the workflow relies on

GitHub, the repository's **Settings → Environments**: an environment named `release`, with
**Required reviewers** (the maintainers who approve a release) and, under **Deployment branches and
tags**, `main` alone. No secret and no token: the workflow publishes with the repository's own.
GitHub makes an environment a job names that is not there, with no rule, and runs the job at once
(0.3.0 was published so, before the environment was set up); so the publishing job first asks
GitHub for the environment's rules and stops, publishing nothing, where it has no required
reviewers.

## Who releases

A release makes something public under the project's name, so it waits for a maintainer: the
approval in the `release` environment is the decision, taken once the draft (its notes and files)
is there to be looked at. Everything before it (prepare, the commit, the tag and the draft) is seen
by maintainers only, and a draft that is rejected stays a draft.
